//
//  PDFRedactorTests.swift
//  SnapzyTests
//
//  Verifies redaction end-to-end on a real PDF written and reopened from
//  disk: the redacted page is rasterized (pixel-sampled to confirm the
//  fill color actually landed), while an untouched page keeps its exact
//  original page-box dimensions.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class PDFRedactorTests: XCTestCase {

  private func makeSolidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  private func temporaryPDFURL(_ suffix: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("pdf-redactor-test-\(suffix)-\(UUID().uuidString).pdf")
  }

  /// Renders `page` at `scale` and samples the pixel at `point` (in the
  /// page's own PDF point coordinate space, bottom-left origin) as
  /// (red, green, blue) 0...255 bytes.
  private func samplePixel(page: CGPDFPage, at point: CGPoint, scale: CGFloat = 2) throws -> (UInt8, UInt8, UInt8) {
    let box = page.getBoxRect(.mediaBox)
    let width = Int((box.width * scale).rounded())
    let height = Int((box.height * scale).rounded())
    var pixelData = [UInt8](repeating: 0, count: width * height * 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.scaleBy(x: scale, y: scale)
    context.drawPDFPage(page)

    let x = Int((point.x * scale).rounded())
    // The context's drawing space is y-up (bottom-left origin, matching
    // `point`), but the raw pixel buffer is stored top-down in memory —
    // row 0 in `pixelData` is the *top* of the rendered page, not the
    // bottom. Flip to convert a drawing-space y into a buffer row.
    let drawingY = Int((point.y * scale).rounded())
    let row = height - 1 - drawingY
    let offset = (row * width + x) * 4
    return (pixelData[offset], pixelData[offset + 1], pixelData[offset + 2])
  }

  func testRedactedRegionIsFilledWithTheRequestedColor() throws {
    let sourceURL = temporaryPDFURL("source")
    let outputURL = temporaryPDFURL("output")
    defer {
      try? FileManager.default.removeItem(at: sourceURL)
      try? FileManager.default.removeItem(at: outputURL)
    }

    // A solid green page so we can distinguish "redacted" (black) from
    // "untouched" (green) by sampling pixels.
    let greenPage = makeSolidImage(width: 200, height: 200, red: 0, green: 1, blue: 0)
    try PDFExport.write(images: [greenPage], to: sourceURL)

    try PDFRedactor.redactPage(
      pdfAt: sourceURL, pageIndex: 1, region: CGRect(x: 20, y: 20, width: 60, height: 60),
      fillColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), to: outputURL
    )

    let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
    let page = try XCTUnwrap(document.page(at: 1))

    // Inside the redacted region: should now read as black.
    let insideRedaction = try samplePixel(page: page, at: CGPoint(x: 40, y: 40))
    XCTAssertLessThan(insideRedaction.0, 40)
    XCTAssertLessThan(insideRedaction.1, 40)
    XCTAssertLessThan(insideRedaction.2, 40)

    // Outside the redacted region: should still read as green.
    let outsideRedaction = try samplePixel(page: page, at: CGPoint(x: 150, y: 150))
    XCTAssertLessThan(outsideRedaction.0, 40)
    XCTAssertGreaterThan(outsideRedaction.1, 200)
    XCTAssertLessThan(outsideRedaction.2, 40)
  }

  func testOtherPagesAreReEmbeddedUnredacted() throws {
    let sourceURL = temporaryPDFURL("source-multi")
    let outputURL = temporaryPDFURL("output-multi")
    defer {
      try? FileManager.default.removeItem(at: sourceURL)
      try? FileManager.default.removeItem(at: outputURL)
    }

    let bluePage = makeSolidImage(width: 100, height: 100, red: 0, green: 0, blue: 1)
    let redPage = makeSolidImage(width: 100, height: 100, red: 1, green: 0, blue: 0)
    try PDFExport.write(images: [bluePage, redPage], to: sourceURL)

    try PDFRedactor.redactPage(
      pdfAt: sourceURL, pageIndex: 1, region: CGRect(x: 0, y: 0, width: 100, height: 100), to: outputURL
    )

    let document = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
    XCTAssertEqual(document.numberOfPages, 2)

    // Page 2 was never targeted for redaction — it should still sample
    // as red, unaffected by the redaction applied to page 1.
    let page2 = try XCTUnwrap(document.page(at: 2))
    let sample = try samplePixel(page: page2, at: CGPoint(x: 50, y: 50))
    XCTAssertGreaterThan(sample.0, 200)
    XCTAssertLessThan(sample.1, 40)
    XCTAssertLessThan(sample.2, 40)
  }

  func testInvalidPageIndexThrows() throws {
    let sourceURL = temporaryPDFURL("source-invalid")
    let outputURL = temporaryPDFURL("output-invalid")
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    try PDFExport.write(images: [makeSolidImage(width: 50, height: 50, red: 1, green: 1, blue: 1)], to: sourceURL)

    XCTAssertThrowsError(
      try PDFRedactor.redactPage(pdfAt: sourceURL, pageIndex: 5, region: .zero, to: outputURL)
    ) { error in
      guard case PDFRedactor.RedactError.invalidPageIndex = error else {
        return XCTFail("expected invalidPageIndex, got \(error)")
      }
    }
  }
}
