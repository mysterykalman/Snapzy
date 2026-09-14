// Packages/BrowserBridgeKit/Sources/BrowserBridgeKit/BridgeMessage.swift
import Foundation

/// The versioned JSON message envelope carried over the local Unix-domain
/// socket between the Capture (Snapzy) app and the Chrome native-messaging host.
///
/// ```json
/// { "version": 1, "id": "uuid", "type": "ping", "payload": {} }
/// ```
public struct BridgeMessage: Codable, Equatable, Sendable {
    public var version: Int
    public var id: String
    public var type: String
    public var payload: JSONValue

    public init(id: String = UUID().uuidString, type: String, payload: JSONValue = .object([:])) {
        self.version = BridgeConfiguration.protocolVersion
        self.id = id
        self.type = type
        self.payload = payload
    }
}

public struct BridgeResponse: Codable, Equatable, Sendable {
    public struct ErrorPayload: Codable, Equatable, Sendable {
        public var code: String
        public var message: String
        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public var version: Int
    public var id: String
    public var ok: Bool
    public var payload: JSONValue?
    public var error: ErrorPayload?

    public static func success(id: String, payload: JSONValue = .object([:])) -> BridgeResponse {
        BridgeResponse(version: BridgeConfiguration.protocolVersion, id: id, ok: true, payload: payload, error: nil)
    }

    public static func failure(id: String, code: String, message: String) -> BridgeResponse {
        BridgeResponse(
            version: BridgeConfiguration.protocolVersion, id: id, ok: false, payload: nil,
            error: ErrorPayload(code: code, message: message)
        )
    }
}

/// Well-known error codes so both sides of the bridge (and the extension's
/// JS, which mirrors these as plain strings) can pattern-match on failure
/// kind rather than parsing prose.
public enum BridgeErrorCode {
    public static let invalidMessage = "INVALID_MESSAGE"
    public static let malformedMessage = "MALFORMED_MESSAGE"
    public static let unsupportedVersion = "UNSUPPORTED_VERSION"
    public static let messageTooLarge = "MESSAGE_TOO_LARGE"
    public static let relayFailed = "RELAY_FAILED"
    public static let appNotRunning = "APP_NOT_RUNNING"
    public static let nativeHostDisconnected = "NATIVE_HOST_DISCONNECTED"
}

/// Minimal `Codable` untyped-JSON representation, so `BridgeMessage` can
/// round-trip an arbitrary payload shape without a Swift type per message
/// `type`. The trust boundary (every message crossing this bridge
/// originates from a web page via a content script/extension and must be
/// treated as untrusted) is enforced by `BridgeMessageValidator` reading
/// out of this value explicitly, not by Swift's type system alone.
public indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
