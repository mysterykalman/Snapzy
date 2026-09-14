// native-host/Sources/snapzy-native-host/main.swift
import BrowserBridgeKit
import Foundation

// The native-messaging host Chrome launches per extension connection.
// Reads framed JSON messages from stdin (Chrome's Native Messaging
// protocol — see `NativeMessagingCodec`), validates and relays each one as
// a single newline-delimited JSON line to the Snapzy app's Unix-domain-
// socket bridge (`BridgeSocketServer`), frames the line it gets back, and
// writes that to stdout. Chrome owns the process lifecycle — it starts
// this host when the extension calls `chrome.runtime.connectNative` and
// kills it when the port disconnects — so this loop simply runs until
// stdin closes (EOF), with no attempt to daemonize or exit on its own.
//
// `--print-config` is a diagnostic/installer entry point, not part of the
// Native Messaging protocol: it prints the canonical paths/names from
// `BridgeConfiguration` as JSON so an install script can derive them from
// this binary rather than hardcoding a second copy in shell.

if CommandLine.arguments.dropFirst().contains("--print-config") {
  printConfig()
  exit(0)
}

func printConfig() {
  let config: [String: Any] = [
    "protocolVersion": BridgeConfiguration.protocolVersion,
    "nativeMessagingHostName": BridgeConfiguration.nativeMessagingHostName,
    "nativeMessagingHostBinaryName": BridgeConfiguration.nativeMessagingHostBinaryName,
    "nativeMessagingManifestName": BridgeConfiguration.chromeNativeMessagingManifestName,
    "nativeMessagingInstallDirectory": BridgeConfiguration.nativeMessagingInstallDirectory.path,
    "chromeNativeMessagingHostsDirectory": BridgeConfiguration.chromeNativeMessagingHostsDirectory.path,
    "socketPath": BridgeConfiguration.socketURL.path,
    "appBundleIdentifier": BridgeConfiguration.appBundleIdentifier,
  ]
  guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) else {
    FileHandle.standardError.write(Data("Could not encode config.\n".utf8))
    exit(1)
  }
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
}

let socketClient = BridgeSocketClient(socketURL: BridgeConfiguration.socketURL)

var inputBuffer = Data()
let readChunkSize = 4096

func readMoreFromStdin() -> Data? {
  var chunk = [UInt8](repeating: 0, count: readChunkSize)
  let bytesRead = chunk.withUnsafeMutableBytes { rawBuffer in
    read(FileHandle.standardInput.fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
  }
  guard bytesRead > 0 else { return nil }  // EOF or error — either way, stop
  return Data(chunk[0..<bytesRead])
}

func writeToStdout(_ data: Data) {
  data.withUnsafeBytes { rawBuffer in
    _ = write(FileHandle.standardOutput.fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
  }
}

@MainActor
func writeFramedResponse(_ response: BridgeResponse) {
  guard let payload = try? JSONEncoder().encode(response),
    let framed = try? NativeMessagingCodec.frame(payload)
  else { return }
  writeToStdout(framed)
}

/// One JSON payload in from Chrome -> validated -> one relayed line out to
/// the app -> one framed JSON payload back to Chrome. Malformed input, a
/// validation failure, or a relay failure (including the app simply not
/// running) all produce a real, structured error response rather than
/// silently dropping the message, so the extension side always gets an
/// answer to stop waiting on.
@MainActor
func handleIncomingMessage(_ payload: Data) {
  guard payload.count <= NativeMessagingCodec.maxMessageBytes else {
    writeFramedResponse(.failure(id: "unknown", code: BridgeErrorCode.messageTooLarge, message: "Message exceeds the native-messaging size limit."))
    return
  }

  let message: BridgeMessage
  do {
    message = try JSONDecoder().decode(BridgeMessage.self, from: payload)
  } catch {
    writeFramedResponse(.failure(id: "unknown", code: BridgeErrorCode.malformedMessage, message: "Not valid BridgeMessage JSON: \(error.localizedDescription)"))
    return
  }

  do {
    try BridgeMessageValidator.validate(message, encodedSize: payload.count)
  } catch {
    writeFramedResponse(.failure(id: message.id, code: BridgeErrorCode.invalidMessage, message: error.localizedDescription))
    return
  }

  let line = String(decoding: payload, as: UTF8.self)
  do {
    let responseLine = try socketClient.sendAndReceiveLine(line)
    guard let responseData = responseLine.data(using: .utf8),
      let response = try? JSONDecoder().decode(BridgeResponse.self, from: responseData)
    else {
      writeFramedResponse(.failure(id: message.id, code: BridgeErrorCode.malformedMessage, message: "App returned an invalid response line."))
      return
    }
    writeFramedResponse(response)
  } catch let error as BridgeSocketClient.ClientError {
    // A connect failure is the expected shape of "Snapzy isn't running" —
    // surfaced as a distinct, recognizable code rather than a raw POSIX
    // error string, so the extension can show a clear message ("Open
    // Capture and try again") instead of a generic failure.
    let code: String
    switch error {
    case .connectFailed:
      code = BridgeErrorCode.appNotRunning
    default:
      code = BridgeErrorCode.relayFailed
    }
    writeFramedResponse(.failure(id: message.id, code: code, message: error.localizedDescription))
  } catch {
    writeFramedResponse(.failure(id: message.id, code: BridgeErrorCode.relayFailed, message: error.localizedDescription))
  }
}

while let newBytes = readMoreFromStdin() {
  inputBuffer.append(newBytes)
  while true {
    do {
      guard let message = try NativeMessagingCodec.nextMessage(from: &inputBuffer) else { break }
      handleIncomingMessage(message)
    } catch {
      // A declared frame length over Chrome's own limit — nothing sane
      // to recover from (the buffer's framing is now untrustworthy), so
      // stop rather than loop forever.
      writeFramedResponse(.failure(id: "unknown", code: BridgeErrorCode.messageTooLarge, message: "\(error)"))
      exit(1)
    }
  }
}
