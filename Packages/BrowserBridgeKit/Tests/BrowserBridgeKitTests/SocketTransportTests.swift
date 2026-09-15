import XCTest
@testable import BrowserBridgeKit

final class SocketTransportTests: XCTestCase {
    private func temporarySocketURL() -> URL {
        // Darwin sun_path is limited to 104 bytes. Runner NSTemporaryDirectory
        // prefixes plus a UUID can exceed it before the socket name is appended.
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("browser-bridge-test-\(UUID().uuidString)")
            .appendingPathComponent("socket")
    }

    private func withServer(
        handler: @escaping BridgeSocketServer.Handler,
        _ body: (URL, BridgeSocketClient) throws -> Void
    ) throws {
        let socketURL = temporarySocketURL()
        let server = BridgeSocketServer(socketURL: socketURL, handler: handler)
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }
        let client = BridgeSocketClient(socketURL: socketURL)
        try body(socketURL, client)
    }

    func testPingRoundTripPreservesRequestID() throws {
        try withServer(handler: { message in
            .success(id: message.id, payload: .object(["pong": .bool(true)]))
        }) { _, client in
            let requestID = "fixed-request-id"
            let response = try client.send(BridgeMessage(id: requestID, type: "ping"))
            XCTAssertTrue(response.ok)
            XCTAssertEqual(response.id, requestID)
            XCTAssertEqual(response.version, BridgeConfiguration.protocolVersion)
            XCTAssertEqual(response.payload, .object(["pong": .bool(true)]))
        }
    }

    func testUnknownMessageTypeIsRejectedByTheServerItself() throws {
        // The handler is never even invoked for an unregistered type —
        // BridgeSocketServer validates before calling it.
        var handlerWasCalled = false
        try withServer(handler: { message in
            handlerWasCalled = true
            return .success(id: message.id, payload: .object([:]))
        }) { _, client in
            let response = try client.send(BridgeMessage(type: "totally.unknown.type"))
            XCTAssertFalse(response.ok)
            XCTAssertEqual(response.error?.code, BridgeErrorCode.invalidMessage)
        }
        XCTAssertFalse(handlerWasCalled)
    }

    func testMalformedJSONLineGetsAStructuredErrorResponse() throws {
        try withServer(handler: { message in .success(id: message.id, payload: .object([:])) }) { _, client in
            let response = try client.sendAndReceiveLine("{ this is not valid JSON")
            let decoded = try JSONDecoder().decode(BridgeResponse.self, from: Data(response.utf8))
            XCTAssertFalse(decoded.ok)
            XCTAssertEqual(decoded.error?.code, BridgeErrorCode.malformedMessage)
        }
    }

    func testOversizedLineIsRejectedWithoutReachingTheHandler() throws {
        var handlerWasCalled = false
        try withServer(handler: { message in
            handlerWasCalled = true
            return .success(id: message.id, payload: .object([:]))
        }) { _, client in
            // A payload comfortably over BridgeMessageValidator.maxPayloadBytes.
            let hugeString = String(repeating: "a", count: BridgeMessageValidator.maxPayloadBytes + 1024)
            let message = BridgeMessage(type: "ping", payload: .object(["padding": .string(hugeString)]))
            let data = try JSONEncoder().encode(message)
            let response = try client.sendAndReceiveLine(String(decoding: data, as: UTF8.self))
            let decoded = try JSONDecoder().decode(BridgeResponse.self, from: Data(response.utf8))
            XCTAssertFalse(decoded.ok)
            XCTAssertEqual(decoded.error?.code, BridgeErrorCode.invalidMessage)
        }
        XCTAssertFalse(handlerWasCalled)
    }

    func testProtocolVersionMismatchIsRejected() throws {
        try withServer(handler: { message in .success(id: message.id, payload: .object([:])) }) { _, client in
            var message = BridgeMessage(type: "ping")
            message.version = 999
            let response = try client.send(message)
            XCTAssertFalse(response.ok)
            XCTAssertEqual(response.error?.code, BridgeErrorCode.invalidMessage)
        }
    }

    func testConnectingWhenNoServerIsRunningFailsCleanly() {
        let client = BridgeSocketClient(socketURL: temporarySocketURL())
        XCTAssertThrowsError(try client.send(BridgeMessage(type: "ping"))) { error in
            guard case BridgeSocketClient.ClientError.connectFailed = error else {
                return XCTFail("expected connectFailed, got \(error)")
            }
        }
    }

    func testSocketFileHasUserOnlyPermissions() throws {
        try withServer(handler: { message in .success(id: message.id, payload: .object([:])) }) { socketURL, _ in
            let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
            let permissions = attributes[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.uint16Value, 0o600)
        }
    }

    func testStopRemovesTheSocketFile() throws {
        let socketURL = temporarySocketURL()
        let server = BridgeSocketServer(socketURL: socketURL, handler: { message in
            .success(id: message.id, payload: .object([:]))
        })
        try server.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketURL.path))
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
    }
}
