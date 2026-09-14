//
//  PDFExportTests.swift
//  SnapzyTests
//
//  Writes real PDFs to disk and reopens them with CGPDFDocument to
//  verify actual page count, dimensions, and encryption behavior —
//  not just that the write call didn't throw.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class PDFExportTests: XCTestCase {

  private func makeSolidImage(width: Int, height: Int, red: CGFloat) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  private func temporaryPDFURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("pdf-export-test-\(UUID().uuidString).pdf")
  }

  func testWriteProducesOnePagePerImageAtCorrectDimensions() throws {
    let url = temporaryPDFURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let images = [
      makeSolidImage(width: 200, height: 100, red: 0.1),
      makeSolidImage(width: 300, height: 150, red: 0.5),
    ]
    try PDFExport.write(images: images, to: url)

    let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
    XCTAssertEqual(document.numberOfPages, 2)

    let page1 = try XCTUnwrap(document.page(at: 1))
    let box1 = page1.getBoxRect(.mediaBox)
    XCTAssertEqual(box1.width, 200, accuracy: 0.5)
    XCTAssertEqual(box1.height, 100, accuracy: 0.5)

    let page2 = try XCTUnwrap(document.page(at: 2))
    let box2 = page2.getBoxRect(.mediaBox)
    XCTAssertEqual(box2.width, 300, accuracy: 0.5)
    XCTAssertEqual(box2.height, 150, accuracy: 0.5)
  }

  func testWriteThrowsOnEmptyImageList() {
    let url = temporaryPDFURL()
    XCTAssertThrowsError(try PDFExport.write(images: [], to: url)) { error in
      XCTAssertEqual(error as? PDFExport.ExportError, .emptyImageList)
    }
  }

  func testWriteWithPasswordProducesAnEncryptedDocument() throws {
    let url = temporaryPDFURL()
    defer { try? FileManager.default.removeItem(at: url) }

    try PDFExport.write(images: [makeSolidImage(width: 50, height: 50, red: 1)], to: url, userPassword: "secret123", ownerPassword: nil)

    let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
    XCTAssertTrue(document.isEncrypted)
    XCTAssertFalse(document.isUnlocked)
    XCTAssertTrue(document.unlockWithPassword("secret123"))
  }

  func testWriteWithoutPasswordProducesAnUnencryptedDocument() throws {
    let url = temporaryPDFURL()
    defer { try? FileManager.default.removeItem(at: url) }

    try PDFExport.write(images: [makeSolidImage(width: 50, height: 50, red: 1)], to: url)

    let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
    XCTAssertFalse(document.isEncrypted)
  }

  func testWriteSplitIntoPagesSlicesATallImageAcrossMultiplePages() throws {
    let url = temporaryPDFURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let tallImage = makeSolidImage(width: 400, height: 1000, red: 0.3)
    try PDFExport.writeSplitIntoPages(tallImage: tallImage, pageHeight: 300, to: url)

    let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
    // 1000 / 300 -> 4 pages (300, 300, 300, 100 remainder).
    XCTAssertEqual(document.numberOfPages, 4)

    let lastPage = try XCTUnwrap(document.page(at: 4))
    XCTAssertEqual(lastPage.getBoxRect(.mediaBox).height, 100, accuracy: 0.5)
  }
}

extension PDFExport.ExportError: Equatable {
  public static func == (lhs: PDFExport.ExportError, rhs: PDFExport.ExportError) -> Bool {
    switch (lhs, rhs) {
    case (.contextCreationFailed, .contextCreationFailed), (.emptyImageList, .emptyImageList):
      return true
    default:
      return false
    }
  }
}
