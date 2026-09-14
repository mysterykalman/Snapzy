import XCTest
@testable import BrowserBridgeKit

final class BridgeMessageTests: XCTestCase {
    func testMessageRoundTripsThroughJSON() throws {
        let message = BridgeMessage(id: "abc-123", type: "ping", payload: .object(["x": .number(1)]))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(BridgeMessage.self, from: data)
        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.version, BridgeConfiguration.protocolVersion)
    }

    func testDefaultPayloadIsEmptyObject() {
        let message = BridgeMessage(type: "ping")
        XCTAssertEqual(message.payload, .object([:]))
    }

    func testSuccessResponseHasNoError() throws {
        let response = BridgeResponse.success(id: "1", payload: .object(["pong": .bool(true)]))
        XCTAssertTrue(response.ok)
        XCTAssertNil(response.error)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(BridgeResponse.self, from: data)
        XCTAssertEqual(decoded, response)
    }

    func testFailureResponseHasNoPayload() {
        let response = BridgeResponse.failure(id: "1", code: "X", message: "bad")
        XCTAssertFalse(response.ok)
        XCTAssertNil(response.payload)
        XCTAssertEqual(response.error?.code, "X")
    }

    func testJSONValueRoundTripsEveryCase() throws {
        let value = JSONValue.object([
            "s": .string("hi"),
            "n": .number(3.5),
            "b": .bool(true),
            "a": .array([.string("x"), .null]),
            "nested": .object(["k": .null]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }
}
