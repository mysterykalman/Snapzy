// Packages/BrowserBridgeKit/Sources/BrowserBridgeKit/BridgeInfrastructureRouter.swift
import Foundation

/// Pure routing for the Phase 2 infrastructure message set (`ping`,
/// `hello`, `version`, `status`) — the minimal set needed to prove the
/// transport end-to-end before any real inspection/capture message types
/// exist.
///
/// This is the one place that logic lives: `BrowserBridgeCoordinator` (the
/// production app-side coordinator, in the `Snapzy` app target) and
/// `snapzy-bridge-verify` (the committed end-to-end verification tool, in
/// `native-host/`) both call this exact function rather than each
/// maintaining their own copy of "what a ping/hello/version/status
/// response looks like." Later phases add real message types by extending
/// this router (or, once routing needs app-specific state like history or
/// capture coordinators, by having the app-side coordinator handle those
/// cases itself and fall back to this router only for the infrastructure
/// set — either way, this function stays the canonical infrastructure
/// baseline).
public enum BridgeInfrastructureRouter {
    public static func route(_ message: BridgeMessage, appName: String = "Snapzy", appVersion: String? = nil) -> BridgeResponse {
        switch message.type {
        case "ping":
            return .success(id: message.id, payload: .object(["pong": .bool(true)]))

        case "hello":
            return .success(id: message.id, payload: .object([
                "type": .string("hello.ack"),
                "appName": .string(appName),
                "protocolVersion": .number(Double(BridgeConfiguration.protocolVersion)),
            ]))

        case "version":
            return .success(id: message.id, payload: .object([
                "protocolVersion": .number(Double(BridgeConfiguration.protocolVersion)),
                "appVersion": .string(appVersion ?? "unknown"),
            ]))

        case "status":
            return .success(id: message.id, payload: .object(["running": .bool(true)]))

        default:
            // BridgeMessageValidator already rejects any type not in its
            // registry before a caller typically reaches this router, so
            // arriving here means a type was registered (accepted as a
            // known capability) but never given a route — a real gap to
            // fix, not untrusted input to reject the same way.
            return .failure(
                id: message.id, code: BridgeErrorCode.invalidMessage,
                message: "Message type '\(message.type)' is registered but has no route."
            )
        }
    }
}
