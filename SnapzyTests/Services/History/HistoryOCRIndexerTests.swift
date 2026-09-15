//
//  HistoryOCRIndexerTests.swift
//  SnapzyTests
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Snapzy

private struct FakeTextExtractor: HistoryTextExtracting {
  var textToReturn: String

  func extractText(from image: CGImage) async throws -> String {
    textToReturn
  }
}

@MainActor
final class HistoryOCRIndexerTests: XCTestCase {

  private var testDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    testDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_HistoryOCRIndexer_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let testDirectory {
      try? FileManager.default.removeItem(at: testDirectory)
    }
    try super.tearDownWithError()
  }

  private func makePNGFile() -> URL {
    let url = testDirectory.appendingPathComponent("\(UUID().uuidString).png")
    let width = 4, height = 4
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    let context = CGContext(
      data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return url
  }

  private func makeRecord(filePath: String, captureType: CaptureHistoryType = .screenshot, ocrText: String? = nil) -> CaptureHistoryRecord {
    var record = CaptureHistoryRecord(
      id: UUID(),
      filePath: filePath,
      fileName: (filePath as NSString).lastPathComponent,
      captureType: captureType,
      fileSize: 1024,
      capturedAt: Date(),
      width: 4,
      height: 4,
      duration: nil,
      thumbnailPath: nil,
      isDeleted: false
    )
    record.ocrText = ocrText
    return record
  }

  private func waitForUpdate(on store: FakeHistoryStore, timeout: TimeInterval = 2) {
    let expectation = expectation(description: "OCR text update")
    let start = Date()
    func poll() {
      if !store.updatedOCRText.isEmpty || Date().timeIntervalSince(start) > timeout {
        expectation.fulfill()
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }
    poll()
    wait(for: [expectation], timeout: timeout + 1)
  }

  func testIndexesAScreenshotRecordWithoutExistingOCRText() {
    let store = FakeHistoryStore()
    let extractor = FakeTextExtractor(textToReturn: "Hello from OCR")
    let indexer = HistoryOCRIndexer(store: store, extractor: extractor)
    let record = makeRecord(filePath: makePNGFile().path)

    indexer.indexIfNeeded(record)
    waitForUpdate(on: store)

    XCTAssertEqual(store.updatedOCRText.first?.id, record.id)
    XCTAssertEqual(store.updatedOCRText.first?.text, "Hello from OCR")
  }

  func testSkipsRecordsThatAlreadyHaveOCRText() {
    let store = FakeHistoryStore()
    let extractor = FakeTextExtractor(textToReturn: "Should not be called")
    let indexer = HistoryOCRIndexer(store: store, extractor: extractor)
    let record = makeRecord(filePath: makePNGFile().path, ocrText: "Already indexed")

    indexer.indexIfNeeded(record)

    // No async work should even be scheduled for an already-indexed
    // record, so there's nothing to wait for.
    XCTAssertTrue(store.updatedOCRText.isEmpty)
  }

  func testSkipsNonScreenshotRecords() {
    let store = FakeHistoryStore()
    let extractor = FakeTextExtractor(textToReturn: "Should not be called")
    let indexer = HistoryOCRIndexer(store: store, extractor: extractor)
    let record = makeRecord(filePath: makePNGFile().path, captureType: .video)

    indexer.indexIfNeeded(record)

    XCTAssertTrue(store.updatedOCRText.isEmpty)
  }

  func testStoresNilWhenExtractedTextIsEmpty() {
    let store = FakeHistoryStore()
    let extractor = FakeTextExtractor(textToReturn: "")
    let indexer = HistoryOCRIndexer(store: store, extractor: extractor)
    let record = makeRecord(filePath: makePNGFile().path)

    indexer.indexIfNeeded(record)
    waitForUpdate(on: store)

    XCTAssertEqual(store.updatedOCRText.first?.id, record.id)
    XCTAssertNil(store.updatedOCRText.first?.text)
  }

  func testDoesNothingWhenTheSourceFileIsMissing() {
    let store = FakeHistoryStore()
    let extractor = FakeTextExtractor(textToReturn: "Unreachable")
    let indexer = HistoryOCRIndexer(store: store, extractor: extractor)
    let record = makeRecord(filePath: testDirectory.appendingPathComponent("missing.png").path)

    indexer.indexIfNeeded(record)

    let expectation = expectation(description: "no update happens")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1)
    XCTAssertTrue(store.updatedOCRText.isEmpty)
  }
}
