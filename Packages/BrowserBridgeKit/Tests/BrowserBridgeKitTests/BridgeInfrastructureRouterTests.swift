import XCTest
@testable import BrowserBridgeKit

final class BridgeInfrastructureRouterTests: XCTestCase {
    func testPingReturnsPongTrue() {
        let response = BridgeInfrastructureRouter.route(BridgeMessage(id: "1", type: "ping"))
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.payload, .object(["pong": .bool(true)]))
    }

    func testHelloReturnsAppNameAndProtocolVersion() {
        let response = BridgeInfrastructureRouter.route(BridgeMessage(id: "1", type: "hello"), appName: "TestApp")
        XCTAssertTrue(response.ok)
        guard case .object(let payload)? = response.payload else {
            return XCTFail("expected object payload")
        }
        XCTAssertEqual(payload["appName"], .string("TestApp"))
        XCTAssertEqual(payload["protocolVersion"], .number(Double(BridgeConfiguration.protocolVersion)))
    }

    func testVersionReturnsAppVersion() {
        let response = BridgeInfrastructureRouter.route(BridgeMessage(id: "1", type: "version"), appVersion: "9.9.9")
        guard case .object(let payload)? = response.payload else {
            return XCTFail("expected object payload")
        }
        XCTAssertEqual(payload["appVersion"], .string("9.9.9"))
    }

    func testVersionDefaultsToUnknownAppVersion() {
        let response = BridgeInfrastructureRouter.route(BridgeMessage(id: "1", type: "version"))
        guard case .object(let payload)? = response.payload else {
            return XCTFail("expected object payload")
        }
        XCTAssertEqual(payload["appVersion"], .string("unknown"))
    }

    func testStatusReturnsRunningTrue() {
        let response = BridgeInfrastructureRouter.route(BridgeMessage(id: "1", type: "status"))
        XCTAssertEqual(response.payload, .object(["running": .bool(true)]))
    }

    func testRequestIDIsAlwaysPreserved() {
        for type in ["ping", "hello", "version", "status"] {
            let response = BridgeInfrastructureRouter.route(BridgeMessage(id: "fixed-id", type: type))
            XCTAssertEqual(response.id, "fixed-id", "type \(type) must preserve the request id")
        }
    }

    func testUnroutedRegisteredTypeFailsExplicitlyRatherThanCrashing() {
        // A type BridgeMessageValidator would reject before this ever runs
        // in production, but the router itself must still fail safely if
        // ever called directly with something it doesn't recognize.
        let response = BridgeInfrastructureRouter.route(BridgeMessage(id: "1", type: "not.a.real.type"))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, BridgeErrorCode.invalidMessage)
    }
}
