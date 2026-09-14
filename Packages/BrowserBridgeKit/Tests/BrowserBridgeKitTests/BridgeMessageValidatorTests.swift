import XCTest
@testable import BrowserBridgeKit

final class BridgeMessageValidatorTests: XCTestCase {
    func testKnownTypeWithNoRequiredKeysPasses() throws {
        let message = BridgeMessage(type: "ping")
        XCTAssertNoThrow(try BridgeMessageValidator.validate(message))
    }

    func testAllPhase2TypesAreRegistered() throws {
        for type in ["ping", "pong", "hello", "hello.ack", "version", "version.result", "status", "status.result"] {
            XCTAssertNoThrow(try BridgeMessageValidator.validate(BridgeMessage(type: type)), "type \(type) should validate")
        }
    }

    func testUnregisteredTypeIsRejected() {
        let message = BridgeMessage(type: "inspect.element.request")
        XCTAssertThrowsError(try BridgeMessageValidator.validate(message)) { error in
            guard case BridgeMessageValidator.ValidationError.unregisteredType(let type) = error else {
                return XCTFail("expected unregisteredType, got \(error)")
            }
            XCTAssertEqual(type, "inspect.element.request")
        }
    }

    func testProtocolVersionMismatchIsRejected() {
        var message = BridgeMessage(type: "ping")
        message.version = 99
        XCTAssertThrowsError(try BridgeMessageValidator.validate(message)) { error in
            guard case BridgeMessageValidator.ValidationError.unsupportedProtocolVersion(let version) = error else {
                return XCTFail("expected unsupportedProtocolVersion, got \(error)")
            }
            XCTAssertEqual(version, 99)
        }
    }

    func testOversizedEncodedSizeIsRejected() {
        let message = BridgeMessage(type: "ping")
        XCTAssertThrowsError(try BridgeMessageValidator.validate(message, encodedSize: BridgeMessageValidator.maxPayloadBytes + 1)) { error in
            guard case BridgeMessageValidator.ValidationError.messageTooLarge = error else {
                return XCTFail("expected messageTooLarge, got \(error)")
            }
        }
    }

    func testAtSizeLimitIsAccepted() {
        let message = BridgeMessage(type: "ping")
        XCTAssertNoThrow(try BridgeMessageValidator.validate(message, encodedSize: BridgeMessageValidator.maxPayloadBytes))
    }

    // MARK: - Required-key logic, exercised via a synthetic registry since
    // none of Phase 2's own registered types have required payload keys.

    private let syntheticRegistry: [String: Set<String>] = ["example.request": ["id"]]

    func testMissingRequiredPayloadKeyIsRejected() {
        let message = BridgeMessage(type: "example.request", payload: .object([:]))
        XCTAssertThrowsError(try BridgeMessageValidator.validate(message, registry: syntheticRegistry)) { error in
            guard case BridgeMessageValidator.ValidationError.missingPayloadKey(let type, let key) = error else {
                return XCTFail("expected missingPayloadKey, got \(error)")
            }
            XCTAssertEqual(type, "example.request")
            XCTAssertEqual(key, "id")
        }
    }

    func testPresentRequiredPayloadKeyPasses() throws {
        let message = BridgeMessage(type: "example.request", payload: .object(["id": .string("1")]))
        XCTAssertNoThrow(try BridgeMessageValidator.validate(message, registry: syntheticRegistry))
    }

    func testNonObjectPayloadWithRequiredKeysIsRejected() {
        let message = BridgeMessage(type: "example.request", payload: .array([]))
        XCTAssertThrowsError(try BridgeMessageValidator.validate(message, registry: syntheticRegistry)) { error in
            guard case BridgeMessageValidator.ValidationError.payloadNotAnObject(let type) = error else {
                return XCTFail("expected payloadNotAnObject, got \(error)")
            }
            XCTAssertEqual(type, "example.request")
        }
    }
}
