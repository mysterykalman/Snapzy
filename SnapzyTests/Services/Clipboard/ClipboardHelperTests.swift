//
//  ClipboardHelperTests.swift
//  SnapzyTests
//
//  Unit tests for ClipboardHelper format handling and file copy logic.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class ClipboardHelperTests: XCTestCase {

  private var originalFormat: String?

  override func setUp() {
    super.setUp()
    originalFormat = UserDefaults.standard.string(forKey: PreferencesKeys.screenshotFormat)
  }

  override func tearDown() {
    if let originalFormat {
      UserDefaults.standard.set(originalFormat, forKey: PreferencesKeys.screenshotFormat)
    } else {
      UserDefaults.standard.removeObject(forKey: PreferencesKeys.screenshotFormat)
    }
    super.tearDown()
  }

  func testCopyFileURLs_emptyArray_noOp() {
    ClipboardHelper.copyFileURLs([])
    // Should not crash
  }

  func testCopyMarkdownImage_writesAMarkdownImageReferenceToThePasteboard() {
    let url = URL(fileURLWithPath: "/tmp/example.png")
    ClipboardHelper.copyMarkdownImage(from: url)

    let copied = NSPasteboard.general.string(forType: .string)
    XCTAssertEqual(copied, "![](\(url.absoluteString))")
  }

  func testCopyHTMLImageTag_writesAnImgTagToThePasteboard() {
    let url = URL(fileURLWithPath: "/tmp/example.png")
    ClipboardHelper.copyHTMLImageTag(from: url)

    let copied = NSPasteboard.general.string(forType: .string)
    XCTAssertEqual(copied, "<img src=\"\(url.absoluteString)\">")
  }

  func testCopyHTMLImageTag_neverProducesMoreThanTheTwoAttributeDelimiterQuotes() throws {
    // `URL(fileURLWithPath:)` already percent-encodes a literal `"` in
    // the path to `%22` (verified: file:///tmp/weird%22name.png), so
    // the src attribute's own escaping can't be exercised through a
    // real file URL -- this instead locks in the invariant the
    // escaping exists to protect either way: exactly two `"` characters
    // (the attribute's own delimiters), never more.
    let url = URL(fileURLWithPath: "/tmp/weird\"name.png")
    ClipboardHelper.copyHTMLImageTag(from: url)

    let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
    XCTAssertEqual(copied.filter { $0 == "\"" }.count, 2)
  }

  func testCopyImageFromURL_missingFile_logsAndReturns() {
    let missingURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)_nonexistent.png")
    ClipboardHelper.copyImage(from: missingURL)
    // Should not crash; pasteboard may be empty or unchanged
  }

  func testCopyImageFromURL_validFile_copiesToClipboard() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    guard let data = AnnotateExporter.imageData(from: nsImage, for: "png") else {
      XCTFail("Failed to encode test image")
      return
    }
    let fileURL = tempDir.appendingPathComponent("test.png")
    try data.write(to: fileURL)

    ClipboardHelper.copyImage(from: fileURL)
    let pasteboard = NSPasteboard.general
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    
    // Core Sandbox Compatibility: writeObjects([NSURL]) registers the file URL type
    XCTAssertTrue(item.types.contains(.fileURL))
    
    // Image Augmentation
    XCTAssertTrue(item.types.contains(.png))
    XCTAssertTrue(item.types.contains(.tiff))
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count, 1)
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.count, 1)
  }

  func testCopyRenderedImage_withPNGFormat() throws {
    UserDefaults.standard.set(ImageFormatOption.png.rawValue, forKey: PreferencesKeys.screenshotFormat)
    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    ClipboardHelper.copyImage(nsImage)
    let pasteboard = NSPasteboard.general
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    XCTAssertTrue(item.types.contains(.fileURL))
    XCTAssertTrue(item.types.contains(.png))
    XCTAssertTrue(item.types.contains(.tiff))
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count, 1)
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.count, 1)
  }

  func testCopyRenderedImage_withJPEGFormat() throws {
    UserDefaults.standard.set(ImageFormatOption.jpeg.rawValue, forKey: PreferencesKeys.screenshotFormat)
    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    ClipboardHelper.copyImage(nsImage)
    let pasteboard = NSPasteboard.general
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    let jpegType = NSPasteboard.PasteboardType("public.jpeg")
    XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    XCTAssertTrue(item.types.contains(.fileURL))
    XCTAssertTrue(item.types.contains(jpegType))
    XCTAssertTrue(item.types.contains(.tiff))
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count, 1)
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.count, 1)
  }

  func testCopyRenderedImage_withWebPFormat() throws {
    UserDefaults.standard.set(ImageFormatOption.webp.rawValue, forKey: PreferencesKeys.screenshotFormat)
    guard let cgImage = TestImageFactory.solidColor(width: 10, height: 10) else {
      XCTFail("Failed to create test image")
      return
    }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 10, height: 10))
    ClipboardHelper.copyImage(nsImage)
    let pasteboard = NSPasteboard.general
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    let webpType = NSPasteboard.PasteboardType("org.webmproject.webp")
    XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    XCTAssertTrue(item.types.contains(.fileURL))
    XCTAssertTrue(item.types.contains(webpType))
    XCTAssertTrue(item.types.contains(.tiff))
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count, 1)
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.count, 1)
  }

  func testCopyImageFromURL_undecodableWebP_keepsSingleFileAndOriginalDataItem() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("test.webp")
    try Data([0x52, 0x49, 0x46, 0x46]).write(to: fileURL)

    ClipboardHelper.copyImage(from: fileURL)
    let pasteboard = NSPasteboard.general
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    let webPType = NSPasteboard.PasteboardType("org.webmproject.webp")

    XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    XCTAssertTrue(item.types.contains(.fileURL))
    XCTAssertTrue(item.types.contains(webPType))
    XCTAssertFalse(item.types.contains(.tiff))
    XCTAssertEqual((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count, 1)
  }

  func testCopyMediaFile_validVideoFile_addsFileURLAndFallbackRepresentations() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("recording.mp4")
    try Data([0, 1, 2, 3]).write(to: fileURL)

    ClipboardHelper.copyMediaFile(from: fileURL)

    let pasteboard = NSPasteboard.general
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    XCTAssertTrue(item.types.contains(.fileURL))
    XCTAssertTrue(item.types.contains(.URL))
    XCTAssertTrue(item.types.contains(.string))
    XCTAssertEqual(item.string(forType: .fileURL), fileURL.absoluteString)
    XCTAssertEqual(item.string(forType: .URL), fileURL.absoluteString)
    XCTAssertEqual(item.string(forType: .string), fileURL.path)
    XCTAssertEqual(
      (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first?.standardizedFileURL,
      fileURL.standardizedFileURL
    )
  }

  func testCopyFileURLs_multipleURLs_copiesAllToClipboard() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let url1 = tempDir.appendingPathComponent("file1.png")
    let url2 = tempDir.appendingPathComponent("file2.txt")
    try Data([1, 2, 3]).write(to: url1)
    try Data([4, 5, 6]).write(to: url2)

    ClipboardHelper.copyFileURLs([url1, url2])

    let pasteboard = NSPasteboard.general
    let items = try XCTUnwrap(pasteboard.pasteboardItems)
    XCTAssertEqual(items.count, 2)
    XCTAssertTrue(items[0].types.contains(.fileURL))
    XCTAssertTrue(items[1].types.contains(.fileURL))

    let readURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    XCTAssertEqual(readURLs?.count, 2)
    XCTAssertEqual(readURLs?[0].standardizedFileURL, url1.standardizedFileURL)
    XCTAssertEqual(readURLs?[1].standardizedFileURL, url2.standardizedFileURL)
  }
}
