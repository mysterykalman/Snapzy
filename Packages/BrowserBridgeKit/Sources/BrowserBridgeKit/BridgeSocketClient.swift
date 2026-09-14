// Packages/BrowserBridgeKit/Sources/BrowserBridgeKit/BridgeSocketClient.swift
import Darwin
import Foundation

/// A minimal blocking Unix-domain-socket client for talking to
/// `BridgeSocketServer`. Used by the native-messaging host (relaying one
/// message per Chrome native-messaging frame) and by this package's own
/// verification harness/tests. Framing matches `BridgeSocketServer`
/// exactly: one newline-delimited JSON line out, one newline-delimited
/// JSON line back.
public final class BridgeSocketClient {
    public enum ClientError: Error, LocalizedError, Equatable {
        case pathTooLong(String)
        case socketCreationFailed(String)
        case connectFailed(String)
        case writeFailed(String)
        case connectionClosed
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .pathTooLong(let path): return "Socket path is too long for sockaddr_un: \(path)"
            case .socketCreationFailed(let msg): return "socket() failed: \(msg)"
            case .connectFailed(let msg): return "connect() failed: \(msg). Is Snapzy running?"
            case .writeFailed(let msg): return "write() failed: \(msg)"
            case .connectionClosed: return "Connection closed before a full response line was received."
            case .invalidResponse: return "The response line was not valid BridgeResponse JSON."
            }
        }
    }

    private let socketURL: URL

    public init(socketURL: URL = BridgeConfiguration.socketURL) {
        self.socketURL = socketURL
    }

    /// Connects, sends `message` as one JSON line, reads back exactly one
    /// response line, decodes it as `BridgeResponse`, and disconnects.
    public func send(_ message: BridgeMessage) throws -> BridgeResponse {
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let line = String(decoding: data, as: UTF8.self)
        let responseLine = try sendAndReceiveLine(line)
        guard let responseData = responseLine.data(using: .utf8) else {
            throw ClientError.invalidResponse
        }
        return try JSONDecoder().decode(BridgeResponse.self, from: responseData)
    }

    /// Connects, sends `line` (a single JSON object; a trailing `\n` is
    /// added if not already present), reads back exactly one
    /// newline-delimited response line, and disconnects. Exposed
    /// separately from `send(_:)` so the native host — which relays
    /// already-encoded JSON lines from Chrome without needing to decode
    /// them into `BridgeMessage` itself — never has to round-trip through
    /// a Swift model it doesn't otherwise need.
    public func sendAndReceiveLine(_ line: String) throws -> String {
        let path = socketURL.path
        let pathBytes = Array(path.utf8)
        let maxLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
        guard pathBytes.count <= maxLength else {
            throw ClientError.pathTooLong(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ClientError.socketCreationFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            pathPointer.withMemoryRebound(to: CChar.self, capacity: maxLength + 1) { charPointer in
                _ = pathBytes.withUnsafeBufferPointer { buffer in
                    memcpy(charPointer, buffer.baseAddress, buffer.count)
                }
                charPointer[pathBytes.count] = 0
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw ClientError.connectFailed(String(cString: strerror(errno)))
        }

        var outgoing = Data(line.utf8)
        if outgoing.last != UInt8(ascii: "\n") { outgoing.append(UInt8(ascii: "\n")) }
        let written = outgoing.withUnsafeBytes { rawBuffer -> Int in
            Darwin.write(fd, rawBuffer.baseAddress, rawBuffer.count)
        }
        guard written == outgoing.count else {
            throw ClientError.writeFailed(String(cString: strerror(errno)))
        }

        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !received.contains(UInt8(ascii: "\n")) {
            let bytesRead = chunk.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fd, rawBuffer.baseAddress, rawBuffer.count)
            }
            guard bytesRead > 0 else { throw ClientError.connectionClosed }
            received.append(contentsOf: chunk[0..<bytesRead])
        }

        guard let newlineIndex = received.firstIndex(of: UInt8(ascii: "\n")) else {
            throw ClientError.connectionClosed
        }
        return String(decoding: received[received.startIndex..<newlineIndex], as: UTF8.self)
    }
}
