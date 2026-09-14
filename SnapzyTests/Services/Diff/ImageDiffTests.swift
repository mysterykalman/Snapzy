//
//  ImageDiffTests.swift
//  SnapzyTests
//
//  Ported from the original Capture app's CaptureDiffTests (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md), converted from Swift
//  Testing (@Test/#expect) to this project's XCTest convention.
//

import CoreGraphics
import Foundation
import XCTest
@testable import Snapzy

final class ImageDiffTests: XCTestCase {

  private func makeSolidImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
    let bytesPerPixel = 4
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
    for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
      pixels[i] = red
      pixels[i + 1] = green
      pixels[i + 2] = blue
      pixels[i + 3] = 255
    }
    let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * bytesPerPixel,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
  }

  /// A test image with a colored square in one corner, otherwise solid
  /// background -- lets diff tests assert *which* pixels are flagged,
  /// not just "some difference was found."
  private func makeImageWithSquare(width: Int, height: Int, background: (UInt8, UInt8, UInt8), squareColor: (UInt8, UInt8, UInt8), squareRect: (x: Int, y: Int, size: Int)) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let inSquare = x >= squareRect.x && x < squareRect.x + squareRect.size && y >= squareRect.y && y < squareRect.y + squareRect.size
        let color = inSquare ? squareColor : background
        let offset = (y * width + x) * 4
        pixels[offset] = color.0
        pixels[offset + 1] = color.1
        pixels[offset + 2] = color.2
        pixels[offset + 3] = 255
      }
    }
    let context = CGContext(
      data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
  }

  func testPixelDiffFindsNoDifferenceForIdenticalImages() throws {
    let image = makeSolidImage(width: 20, height: 20, red: 100, green: 100, blue: 100)
    let result = try ImageDiff.pixelDiff(before: image, after: image)
    XCTAssertEqual(result.differingRatio, 0)
  }

  func testPixelDiffFindsExactlyTheChangedRegion() throws {
    let before = makeImageWithSquare(width: 20, height: 20, background: (255, 255, 255), squareColor: (0, 0, 0), squareRect: (x: 0, y: 0, size: 0))
    let after = makeImageWithSquare(width: 20, height: 20, background: (255, 255, 255), squareColor: (0, 0, 0), squareRect: (x: 5, y: 5, size: 5))
    let result = try ImageDiff.pixelDiff(before: before, after: after)
    // A 5x5 square out of 20x20 = 25/400 = 6.25% changed.
    XCTAssertEqual(result.differingRatio, 0.0625, accuracy: 0.0001)
  }

  func testPixelDiffThrowsForMismatchedDimensions() {
    let before = makeSolidImage(width: 10, height: 10, red: 0, green: 0, blue: 0)
    let after = makeSolidImage(width: 20, height: 20, red: 0, green: 0, blue: 0)
    XCTAssertThrowsError(try ImageDiff.pixelDiff(before: before, after: after))
  }

  func testPixelDiffIgnoresChangesInsideAMaskedRegion() throws {
    let before = makeImageWithSquare(width: 20, height: 20, background: (255, 255, 255), squareColor: (0, 0, 0), squareRect: (x: 0, y: 0, size: 0))
    let after = makeImageWithSquare(width: 20, height: 20, background: (255, 255, 255), squareColor: (0, 0, 0), squareRect: (x: 5, y: 5, size: 5))
    let result = try ImageDiff.pixelDiff(before: before, after: after, ignoredRegions: [CGRect(x: 5, y: 5, width: 5, height: 5)])
    XCTAssertEqual(result.differingRatio, 0)
  }

  func testPixelDiffStillFindsChangesOutsideTheMaskedRegion() throws {
    let before = makeImageWithSquare(width: 20, height: 20, background: (255, 255, 255), squareColor: (0, 0, 0), squareRect: (x: 0, y: 0, size: 0))
    let after = makeImageWithSquare(width: 20, height: 20, background: (255, 255, 255), squareColor: (0, 0, 0), squareRect: (x: 5, y: 5, size: 5))
    // Mask a region that doesn't overlap the actual change at all.
    let result = try ImageDiff.pixelDiff(before: before, after: after, ignoredRegions: [CGRect(x: 15, y: 15, width: 2, height: 2)])
    XCTAssertEqual(result.differingRatio, 0.0625, accuracy: 0.0001)
  }

  func testPerceptualDiffIgnoresASingleShiftedAntiAliasedPixel() throws {
    // A single pixel changed by a tiny amount inside an otherwise-identical
    // 16x16 image barely moves its 8x8 block's average -- perceptual diff
    // should treat this as unchanged, unlike pixelDiff which would flag it.
    var pixels = [UInt8](repeating: 200, count: 16 * 16 * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) { pixels[i + 3] = 255 }
    let context1 = CGContext(data: &pixels, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let before = context1.makeImage()!

    pixels[0] = 201  // one channel of one pixel, off by 1
    let context2 = CGContext(data: &pixels, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let after = context2.makeImage()!

    let result = try ImageDiff.perceptualDiff(before: before, after: after, blockSize: 8, tolerance: 12)
    XCTAssertEqual(result.differingRatio, 0)
  }

  func testPerceptualDiffFlagsARealChangedRegion() throws {
    let before = makeImageWithSquare(width: 16, height: 16, background: (0, 0, 0), squareColor: (0, 0, 0), squareRect: (x: 0, y: 0, size: 0))
    let after = makeImageWithSquare(width: 16, height: 16, background: (0, 0, 0), squareColor: (255, 255, 255), squareRect: (x: 0, y: 0, size: 8))
    let result = try ImageDiff.perceptualDiff(before: before, after: after, blockSize: 8, tolerance: 12)
    // Exactly one 8x8 block (top-left) changed out of four total blocks.
    XCTAssertEqual(result.differingRatio, 0.25, accuracy: 0.0001)
  }

  func testOverlayThrowsForMismatchedDimensions() {
    let before = makeSolidImage(width: 10, height: 10, red: 0, green: 0, blue: 0)
    let after = makeSolidImage(width: 20, height: 20, red: 0, green: 0, blue: 0)
    XCTAssertThrowsError(try ImageDiff.overlay(before: before, after: after, opacity: 0.5))
  }

  func testOverlayAtFullOpacityShowsOnlyAfter() throws {
    let before = makeSolidImage(width: 4, height: 4, red: 0, green: 0, blue: 0)
    let after = makeSolidImage(width: 4, height: 4, red: 255, green: 255, blue: 255)
    let result = try ImageDiff.overlay(before: before, after: after, opacity: 1.0)
    let data = result.dataProvider!.data! as Data
    XCTAssertEqual(data[0], 255)  // fully after's color, not blended with before
  }

  func testOverlayAtZeroOpacityShowsOnlyBefore() throws {
    let before = makeSolidImage(width: 4, height: 4, red: 0, green: 0, blue: 0)
    let after = makeSolidImage(width: 4, height: 4, red: 255, green: 255, blue: 255)
    let result = try ImageDiff.overlay(before: before, after: after, opacity: 0.0)
    let data = result.dataProvider!.data! as Data
    XCTAssertEqual(data[0], 0)
  }

  func testSwipeShowsBeforeLeftOfDividerAndAfterRightOfDivider() throws {
    let before = makeSolidImage(width: 10, height: 10, red: 0, green: 0, blue: 0)
    let after = makeSolidImage(width: 10, height: 10, red: 255, green: 255, blue: 255)
    let result = try ImageDiff.swipe(before: before, after: after, dividerFraction: 0.5)
    let data = result.dataProvider!.data! as Data
    // Row 0, x=2 (left of the divider at x=5) should be `before`'s black.
    XCTAssertEqual(data[2 * 4], 0)
    // Row 0, x=8 (right of the divider) should be `after`'s white.
    XCTAssertEqual(data[8 * 4], 255)
  }

  func testSwipeThrowsForMismatchedDimensions() {
    let before = makeSolidImage(width: 10, height: 10, red: 0, green: 0, blue: 0)
    let after = makeSolidImage(width: 20, height: 20, red: 0, green: 0, blue: 0)
    XCTAssertThrowsError(try ImageDiff.swipe(before: before, after: after, dividerFraction: 0.5))
  }
}
