// native-host/Sources/snapzy-bridge-verify/main.swift
import BrowserBridgeKit
import Foundation

// A committed, repeatable end-to-end check of the whole browser-bridge
// transport, standing in for Chrome (which this tool cannot itself drive)
// with direct Chrome-Native-Messaging-framed stdio against the real,
// built `snapzy-native-host` binary:
//
//   this tool (playing "Chrome")
//     --(framed stdio, exactly Chrome's own protocol)-->
//   real snapzy-native-host subprocess
//     --(real BrowserBridgeKit.BridgeSocketClient, real Unix socket)-->
//   real BrowserBridgeKit.BridgeSocketServer + BridgeInfrastructureRouter
//     (the exact routing code the Snapzy app itself uses)
//     --> response, same path back.
//
// Run via: swift run --package-path native-host snapzy-bridge-verify
// (builds snapzy-native-host first if it isn't already built next to it).
//
// IMPORTANT: quit the real Capture app before running this — both bind
// the same canonical socket path, and only one can hold it at a time.

nonisolated(unsafe) var failures = 0
func check(_ name: String, _ condition: @autoclosure () -> Bool) {
  if condition() {
    print("PASS  \(name)")
  } else {
    print("FAIL  \(name)")
    failures += 1
  }
}

func locateNativeHostBinary() -> URL {
  // This tool and snapzy-native-host are built into the same
  // `.build/<config>/` directory as sibling products, whichever
  // configuration (debug/release) is currently running.
  let selfPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
  return selfPath.deletingLastPathComponent().appendingPathComponent("snapzy-native-host")
}

final class NativeHostProcess {
  let process = Process()
  let stdinPipe = Pipe()
  let stdoutPipe = Pipe()
  private var readBuffer = Data()

  init(binaryURL: URL) {
    process.executableURL = binaryURL
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
  }

  func start() throws { try process.run() }
  func terminateAndWait() {
    process.terminate()
    process.waitUntilExit()
  }

  func sendAndReceive(_ message: BridgeMessage, timeout: TimeInterval = 5) throws -> BridgeResponse {
    let payload = try JSONEncoder().encode(message)
    stdinPipe.fileHandleForWriting.write(try NativeMessagingCodec.frame(payload))
    return try readOneFramedResponse(timeout: timeout)
  }

  func sendRawFramed(_ payload: Data, timeout: TimeInterval = 5) throws -> BridgeResponse {
    stdinPipe.fileHandleForWriting.write(try NativeMessagingCodec.frame(payload))
    return try readOneFramedResponse(timeout: timeout)
  }

  private func readOneFramedResponse(timeout: TimeInterval) throws -> BridgeResponse {
    let deadline = Date().addingTimeInterval(timeout)
    let handle = stdoutPipe.fileHandleForReading
    while Date() < deadline {
      if let extracted = try NativeMessagingCodec.nextMessage(from: &readBuffer) {
        return try JSONDecoder().decode(BridgeResponse.self, from: extracted)
      }
      let chunk = handle.availableData
      if chunk.isEmpty {
        usleep(10_000)
        continue
      }
      readBuffer.append(chunk)
    }
    throw NSError(domain: "snapzy-bridge-verify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for native host response."])
  }
}

let nativeHostBinaryURL = locateNativeHostBinary()
guard FileManager.default.isExecutableFile(atPath: nativeHostBinaryURL.path) else {
  print("error: snapzy-native-host binary not found at \(nativeHostBinaryURL.path)")
  print("Build it first: swift build --package-path native-host --product snapzy-native-host")
  exit(1)
}

// --- Host the real transport + real routing logic, standing in for the running app ---
let server = BridgeSocketServer { message in
  BridgeInfrastructureRouter.route(message, appName: "Snapzy", appVersion: "verify-tool")
}
do {
  try server.start()
} catch {
  print("error: could not start the bridge socket server: \(error.localizedDescription)")
  print("Is the real Capture app already running? Quit it first — both bind the same socket.")
  exit(1)
}
print("Bridge socket server listening at \(BridgeConfiguration.socketURL.path)")

check("server: started", server.isRunning)

do {
  let host = NativeHostProcess(binaryURL: nativeHostBinaryURL)
  try host.start()
  let hello = try host.sendAndReceive(BridgeMessage(type: "hello"))
  check("hello: ok", hello.ok)
  check("hello: protocol version preserved", hello.version == BridgeConfiguration.protocolVersion)
  host.terminateAndWait()
} catch {
  check("hello scenario threw \(error)", false)
}

do {
  let host = NativeHostProcess(binaryURL: nativeHostBinaryURL)
  try host.start()
  let requestID = "verify-ping-\(UUID().uuidString)"
  let ping = try host.sendAndReceive(BridgeMessage(id: requestID, type: "ping"))
  check("ping: ok", ping.ok)
  check("ping: request id preserved end-to-end", ping.id == requestID)
  check("ping: payload has pong:true", ping.payload == .object(["pong": .bool(true)]))
  host.terminateAndWait()
} catch {
  check("ping scenario threw \(error)", false)
}

do {
  let host = NativeHostProcess(binaryURL: nativeHostBinaryURL)
  try host.start()
  let version = try host.sendAndReceive(BridgeMessage(type: "version"))
  check("version: ok", version.ok)
  if case .object(let object)? = version.payload, case .number(let v)? = object["protocolVersion"] {
    check("version: protocolVersion matches", Int(v) == BridgeConfiguration.protocolVersion)
  } else {
    check("version: payload missing protocolVersion", false)
  }
  host.terminateAndWait()
} catch {
  check("version scenario threw \(error)", false)
}

do {
  let host = NativeHostProcess(binaryURL: nativeHostBinaryURL)
  try host.start()
  let response = try host.sendRawFramed(Data(#"{ not valid json"#.utf8))
  check("malformed JSON: rejected (ok == false)", !response.ok)
  check("malformed JSON: error code is MALFORMED_MESSAGE", response.error?.code == BridgeErrorCode.malformedMessage)
  host.terminateAndWait()
} catch {
  check("malformed JSON scenario threw \(error)", false)
}

do {
  let host = NativeHostProcess(binaryURL: nativeHostBinaryURL)
  try host.start()
  let response = try host.sendAndReceive(BridgeMessage(type: "totally.unknown.type"))
  check("unknown type: rejected (ok == false)", !response.ok)
  check("unknown type: error code is INVALID_MESSAGE", response.error?.code == BridgeErrorCode.invalidMessage)
  host.terminateAndWait()
} catch {
  check("unknown type scenario threw \(error)", false)
}

server.stop()
check("server: stopped", !server.isRunning)
do {
  let host = NativeHostProcess(binaryURL: nativeHostBinaryURL)
  try host.start()
  let response = try host.sendAndReceive(BridgeMessage(type: "ping"))
  check("app not running: rejected (ok == false)", !response.ok)
  check("app not running: error code is APP_NOT_RUNNING", response.error?.code == BridgeErrorCode.appNotRunning)
  host.terminateAndWait()
} catch {
  check("app-not-running scenario threw \(error)", false)
}

do {
  try server.start()
} catch {
  check("server: restart threw \(error)", false)
}
check("server: restarted", server.isRunning)
do {
  let host = NativeHostProcess(binaryURL: nativeHostBinaryURL)
  try host.start()
  let response = try host.sendAndReceive(BridgeMessage(type: "ping"))
  check("reconnect: ping ok after server restarts", response.ok)
  host.terminateAndWait()
} catch {
  check("reconnect scenario threw \(error)", false)
}

server.stop()

print("---")
print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
