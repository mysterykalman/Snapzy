import XCTest
@testable import BrowserBridgeKit

final class NativeMessagingCodecTests: XCTestCase {
    func testFrameAndNextMessageRoundTrip() throws {
        let payload = Data(#"{"hello":"world"}"#.utf8)
        let framed = try NativeMessagingCodec.frame(payload)

        var buffer = framed
        let extracted = try NativeMessagingCodec.nextMessage(from: &buffer)
        XCTAssertEqual(extracted, payload)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testNextMessageReturnsNilForPartialHeader() throws {
        var buffer = Data([0x01, 0x02])
        XCTAssertNil(try NativeMessagingCodec.nextMessage(from: &buffer))
        XCTAssertEqual(buffer.count, 2, "partial data must be left untouched")
    }

    func testNextMessageReturnsNilForPartialPayload() throws {
        let payload = Data(#"{"a":1}"#.utf8)
        var framed = try NativeMessagingCodec.frame(payload)
        framed.removeLast() // one byte short of the declared length
        XCTAssertNil(try NativeMessagingCodec.nextMessage(from: &framed))
    }

    func testNextMessageExtractsMultipleQueuedMessages() throws {
        let first = Data(#"{"n":1}"#.utf8)
        let second = Data(#"{"n":2}"#.utf8)
        var buffer = try NativeMessagingCodec.frame(first)
        buffer.append(try NativeMessagingCodec.frame(second))

        let extractedFirst = try NativeMessagingCodec.nextMessage(from: &buffer)
        let extractedSecond = try NativeMessagingCodec.nextMessage(from: &buffer)
        XCTAssertEqual(extractedFirst, first)
        XCTAssertEqual(extractedSecond, second)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testFrameRejectsOversizedPayload() {
        let oversized = Data(count: NativeMessagingCodec.maxMessageBytes + 1)
        XCTAssertThrowsError(try NativeMessagingCodec.frame(oversized)) { error in
            guard case NativeMessagingCodec.CodecError.messageTooLarge(let size) = error else {
                return XCTFail("expected messageTooLarge, got \(error)")
            }
            XCTAssertEqual(size, NativeMessagingCodec.maxMessageBytes + 1)
        }
    }

    func testNextMessageRejectsDeclaredLengthOverLimit() {
        var header = UInt32(NativeMessagingCodec.maxMessageBytes + 1).littleEndian
        var buffer = Data(bytes: &header, count: 4)
        buffer.append(Data([0x00])) // header alone is enough to trigger the check
        XCTAssertThrowsError(try NativeMessagingCodec.nextMessage(from: &buffer))
    }
}
