// Packages/BrowserBridgeKit/Sources/BrowserBridgeKit/NativeMessagingCodec.swift
import Foundation

/// Chrome's Native Messaging wire framing (used on both stdin and stdout
/// of a native-messaging host process): each message is a 4-byte
/// little-endian `UInt32` byte-length header immediately followed by that
/// many bytes of UTF-8 JSON. See
/// https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging#native-messaging-host-protocol.
///
/// Deliberately pure `Data`-in/`Data`-out (no `FileHandle`/stdio) so it's
/// testable without a real process's stdin/stdout, and shared as one
/// implementation between the native-host executable and this package's
/// tests/verification harness rather than re-derived in each.
public enum NativeMessagingCodec {
    public enum CodecError: Error, LocalizedError, Equatable {
        case messageTooLarge(Int)
        public var errorDescription: String? {
            switch self {
            case .messageTooLarge(let size):
                return "Message of \(size) bytes exceeds Chrome's 1 MiB native-messaging limit."
            }
        }
    }

    /// Chrome's own documented limit for a single message host -> extension
    /// (and vice versa; 4 MiB is Chrome's documented limit for extension ->
    /// host, but hosts should not rely on being able to send more than 1
    /// MiB either way in practice). Enforced here so an oversized payload
    /// fails loudly and immediately rather than producing a header Chrome
    /// will refuse to read.
    public static let maxMessageBytes = 1024 * 1024

    /// Prepends the 4-byte length header to `payload`, ready to write to
    /// stdout.
    public static func frame(_ payload: Data) throws -> Data {
        guard payload.count <= maxMessageBytes else {
            throw CodecError.messageTooLarge(payload.count)
        }
        var header = UInt32(payload.count).littleEndian
        var framed = Data(bytes: &header, count: 4)
        framed.append(payload)
        return framed
    }

    /// Extracts the first complete framed message from the front of
    /// `buffer` (typically an accumulating read buffer fed by repeated
    /// stdin reads) if a full one is present, removing its bytes from
    /// `buffer`. Returns `nil` (leaving `buffer` untouched) if fewer than a
    /// full header, or fewer than the header's declared payload length,
    /// have arrived yet — the caller should read more bytes and retry.
    public static func nextMessage(from buffer: inout Data) throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.withUnsafeBytes { rawBuffer -> UInt32 in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        }
        guard length <= maxMessageBytes else {
            throw CodecError.messageTooLarge(Int(length))
        }
        let total = 4 + Int(length)
        guard buffer.count >= total else { return nil }
        let payload = buffer.subdata(in: 4..<total)
        buffer.removeSubrange(0..<total)
        return payload
    }
}
