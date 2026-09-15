// Packages/BrowserBridgeKit/Sources/BrowserBridgeKit/BridgeMessageValidator.swift
import Foundation

/// Enforces the bridge's trust boundary: every message arrives from a
/// Chrome extension relaying content from an arbitrary, untrusted web
/// page, so a message type must be explicitly registered — with the
/// payload keys it requires — before it is dispatched to anything. There
/// is no default-allow path: an unregistered type, a protocol-version
/// mismatch, or a registered type missing a required key are all rejected
/// outright.
///
/// Phase 2 registers only the infrastructure message types needed to prove
/// the transport end-to-end. Future phases add inspection/capture message
/// types here (see `docs/browser-bridge.md`) — this validator is the one
/// place new types get registered, not a per-feature ad hoc check.
public enum BridgeMessageValidator {
    /// type -> required top-level payload keys.
    public static let registeredTypes: [String: Set<String>] = [
        "ping": [],
        "pong": [],
        "hello": [],
        "hello.ack": [],
        "version": [],
        "version.result": [],
        "status": [],
        "status.result": [],
        // Phase 3: real inspection message types. Each content script
        // relays its whole result as one opaque JSON string (`auditJSON`/
        // `snapshotJSON`) that the app-side mapper (AccessibilityAuditMapper/
        // EcommerceAuditMapper) decodes, rather than this validator (or the
        // extension) needing to agree on a fully-typed schema per finding.
        "accessibility.audit.result": ["url", "auditJSON"],
        "ecommerce.audit.result": ["url", "snapshotJSON"],
    ]

    /// Chrome's own documented Native Messaging limit (1 MiB per message,
    /// either direction). Enforced again here — independent of
    /// `NativeMessagingCodec`'s identical check on the stdio side — so the
    /// Unix-socket transport itself never has to trust that whatever wrote
    /// to it obeyed that limit.
    public static let maxPayloadBytes = 1024 * 1024

    public enum ValidationError: Error, LocalizedError, Equatable {
        case unsupportedProtocolVersion(Int)
        case unregisteredType(String)
        case missingPayloadKey(type: String, key: String)
        case payloadNotAnObject(type: String)
        case messageTooLarge(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedProtocolVersion(let version):
                return "Message protocol version \(version) is not supported (expected \(BridgeConfiguration.protocolVersion))."
            case .unregisteredType(let type):
                return "Message type '\(type)' is not a registered capability."
            case .missingPayloadKey(let type, let key):
                return "Message type '\(type)' is missing required payload key '\(key)'."
            case .payloadNotAnObject(let type):
                return "Message type '\(type)' payload must be a JSON object."
            case .messageTooLarge(let size):
                return "Message of \(size) bytes exceeds the \(maxPayloadBytes)-byte limit."
            }
        }
    }

    /// Validates a decoded `BridgeMessage`. `encodedSize`, when known
    /// (e.g. the raw line length before decoding), is checked against
    /// `maxPayloadBytes` too — decoding a message doesn't itself guarantee
    /// its wire size was already bounded. `registry` defaults to the real
    /// `registeredTypes` table; tests pass a synthetic registry to exercise
    /// the required-payload-key logic against types with required keys,
    /// since none of Phase 2's own infrastructure types have any.
    public static func validate(
        _ message: BridgeMessage, encodedSize: Int? = nil, registry: [String: Set<String>] = registeredTypes
    ) throws {
        if let encodedSize, encodedSize > maxPayloadBytes {
            throw ValidationError.messageTooLarge(encodedSize)
        }
        guard message.version == BridgeConfiguration.protocolVersion else {
            throw ValidationError.unsupportedProtocolVersion(message.version)
        }
        guard let requiredKeys = registry[message.type] else {
            throw ValidationError.unregisteredType(message.type)
        }
        if !requiredKeys.isEmpty {
            guard case .object(let object) = message.payload else {
                throw ValidationError.payloadNotAnObject(type: message.type)
            }
            for key in requiredKeys where object[key] == nil {
                throw ValidationError.missingPayloadKey(type: message.type, key: key)
            }
        }
    }
}
