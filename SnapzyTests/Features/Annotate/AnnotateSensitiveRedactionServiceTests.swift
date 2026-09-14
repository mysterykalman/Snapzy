//
//  AnnotateSensitiveRedactionServiceTests.swift
//  SnapzyTests
//
//  Verifies the concurrent text+face detection path added this session
//  (face detection adapted from SnapShotKit's RedactionService, MIT --
//  see docs/REFERENCE_PROVENANCE.md) doesn't crash and returns real,
//  sensible results.
//

import AppKit
import XCTest
@testable import Snapzy

final class AnnotateSensitiveRedactionServiceTests: XCTestCase {

  private func makeSolidImage(width: Int = 200, height: Int = 200) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
  }

  func testBlankImageProducesNoRegions() async throws {
    let service = AnnotateSensitiveRedactionService()
    let result = try await service.detectRegions(in: makeSolidImage())
    XCTAssertEqual(result.count, 0)
    XCTAssertTrue(result.regions.isEmpty)
  }

  func testFaceKindExistsAlongsideTextPIIKinds() {
    XCTAssertTrue(AnnotateSensitiveDataKind.allCases.contains(.face))
    XCTAssertTrue(AnnotateSensitiveDataKind.allCases.contains(.email))
  }

  func testImageRectFlipsVisionsBottomLeftOriginToTopLeft() {
    let imageSize = CGSize(width: 200, height: 100)
    // Vision's boundingBox is normalized, bottom-left origin. A box at
    // the very top of the image in Vision's space (maxY close to 1)
    // should map to y close to 0 in the top-left image-pixel space.
    let visionBox = CGRect(x: 0.25, y: 0.9, width: 0.5, height: 0.1)
    let pixelRect = AnnotateSensitiveRedactionService.imageRect(fromVisionBoundingBox: visionBox, imageSize: imageSize)
    XCTAssertEqual(pixelRect.origin.x, 50, accuracy: 0.01)
    XCTAssertEqual(pixelRect.origin.y, 0, accuracy: 0.01)
    XCTAssertEqual(pixelRect.width, 100, accuracy: 0.01)
    XCTAssertEqual(pixelRect.height, 10, accuracy: 0.01)
  }
}
