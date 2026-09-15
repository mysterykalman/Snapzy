//
//  PPTXExportTests.swift
//  SnapzyTests
//
//  Writes a real .pptx to disk and unzips it back with the system
//  `unzip` tool to verify the actual package contents (slide count,
//  media files, EMU dimensions) -- not just that the write call didn't
//  throw. Mirrors PDFExportTests' "reopen and verify" standard.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class PPTXExportTests: XCTestCase {

  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PPTXExportTests_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDirectory {
      try? FileManager.default.removeItem(at: tempDirectory)
    }
    try super.tearDownWithError()
  }

  private func makeSolidImage(width: Int, height: Int, red: CGFloat) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  /// Unzips `pptxURL` into a fresh subdirectory of `tempDirectory` and
  /// returns that directory, so assertions can read individual package
  /// parts directly off disk.
  private func unzip(_ pptxURL: URL) throws -> URL {
    let extractedDir = tempDirectory.appendingPathComponent("extracted-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-q", pptxURL.path, "-d", extractedDir.path]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return extractedDir
  }

  func testWriteProducesOneSlidePerImageWithMatchingMedia() throws {
    let url = tempDirectory.appendingPathComponent("export.pptx")
    let images = [
      makeSolidImage(width: 192, height: 96, red: 0.1),
      makeSolidImage(width: 288, height: 144, red: 0.5),
    ]
    try PPTXExport.write(images: images, to: url)

    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    let extracted = try unzip(url)
    let fm = FileManager.default
    XCTAssertTrue(fm.fileExists(atPath: extracted.appendingPathComponent("[Content_Types].xml").path))
    XCTAssertTrue(fm.fileExists(atPath: extracted.appendingPathComponent("ppt/presentation.xml").path))
    XCTAssertTrue(fm.fileExists(atPath: extracted.appendingPathComponent("ppt/slides/slide1.xml").path))
    XCTAssertTrue(fm.fileExists(atPath: extracted.appendingPathComponent("ppt/slides/slide2.xml").path))
    XCTAssertTrue(fm.fileExists(atPath: extracted.appendingPathComponent("ppt/media/image1.png").path))
    XCTAssertTrue(fm.fileExists(atPath: extracted.appendingPathComponent("ppt/media/image2.png").path))

    let presentationXML = try String(contentsOf: extracted.appendingPathComponent("ppt/presentation.xml"), encoding: .utf8)
    let slideIdCount = presentationXML.components(separatedBy: "<p:sldId ").count - 1
    XCTAssertEqual(slideIdCount, 2)
  }

  func testWriteSizesEachSlideToItsOwnImageAt96DPI() throws {
    let url = tempDirectory.appendingPathComponent("export.pptx")
    // 192x96 px at 96 DPI is exactly 2x1 inches -> 1,828,800 x 914,400 EMU.
    try PPTXExport.write(images: [makeSolidImage(width: 192, height: 96, red: 0.2)], to: url)

    let extracted = try unzip(url)
    let slideXML = try String(contentsOf: extracted.appendingPathComponent("ppt/slides/slide1.xml"), encoding: .utf8)
    XCTAssertTrue(slideXML.contains(#"cx="1828800" cy="914400""#), "expected 2x1in EMU extent in \(slideXML)")
  }

  func testWriteThrowsOnEmptyImageList() {
    let url = tempDirectory.appendingPathComponent("export.pptx")
    XCTAssertThrowsError(try PPTXExport.write(images: [], to: url)) { error in
      XCTAssertEqual(error as? PPTXExport.ExportError, .emptyImageList)
    }
  }

  func testWriteOverwritesAnExistingFileAtTheDestination() throws {
    let url = tempDirectory.appendingPathComponent("export.pptx")
    try PPTXExport.write(images: [makeSolidImage(width: 50, height: 50, red: 1)], to: url)
    let firstSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64

    try PPTXExport.write(images: [
      makeSolidImage(width: 50, height: 50, red: 1),
      makeSolidImage(width: 50, height: 50, red: 1),
    ], to: url)
    let secondSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64

    XCTAssertNotNil(firstSize)
    XCTAssertNotNil(secondSize)
    let extracted = try unzip(url)
    XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("ppt/slides/slide2.xml").path))
  }
}

extension PPTXExport.ExportError: Equatable {
  public static func == (lhs: PPTXExport.ExportError, rhs: PPTXExport.ExportError) -> Bool {
    switch (lhs, rhs) {
    case (.emptyImageList, .emptyImageList),
      (.pngEncodingFailed, .pngEncodingFailed),
      (.writeFailed, .writeFailed),
      (.zipFailed, .zipFailed):
      return true
    default:
      return false
    }
  }
}
