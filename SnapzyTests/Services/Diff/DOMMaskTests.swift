//
//  DOMMaskTests.swift
//  SnapzyTests
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class DOMMaskTests: XCTestCase {

  func testResolveReturnsARegionForEachSelectorWithARealLiveRect() {
    let masks = [DOMMask(selector: ".review-count"), DOMMask(selector: "#timestamp", label: "Last updated")]
    let liveRects: [String: CGRect] = [
      ".review-count": CGRect(x: 10, y: 20, width: 30, height: 40),
      "#timestamp": CGRect(x: 100, y: 200, width: 50, height: 10),
    ]
    let resolution = DOMMaskResolver.resolve(masks, liveRects: liveRects)
    XCTAssertEqual(resolution.regions.count, 2)
    XCTAssertTrue(resolution.regions.contains(CGRect(x: 10, y: 20, width: 30, height: 40)))
    XCTAssertTrue(resolution.unresolvedSelectors.isEmpty)
  }

  func testResolveReportsAnchorNotFoundForASelectorMatchingNothingLive() {
    let masks = [DOMMask(selector: ".review-count"), DOMMask(selector: ".removed-element")]
    let liveRects: [String: CGRect] = [".review-count": CGRect(x: 0, y: 0, width: 10, height: 10)]
    let resolution = DOMMaskResolver.resolve(masks, liveRects: liveRects)
    XCTAssertEqual(resolution.regions.count, 1)
    XCTAssertEqual(resolution.unresolvedSelectors, [".removed-element"])
  }

  func testResolveHandlesAnEmptyMaskListWithoutCrashing() {
    let resolution = DOMMaskResolver.resolve([], liveRects: [:])
    XCTAssertTrue(resolution.regions.isEmpty)
    XCTAssertTrue(resolution.unresolvedSelectors.isEmpty)
  }

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

  func testResolvedDOMMaskRegionsSuppressARealPixelDiffTheSameWayAFixedMaskWould() throws {
    let before = makeImageWithSquare(width: 20, height: 20, background: (255, 255, 255), squareColor: (0, 0, 0), squareRect: (x: 0, y: 0, size: 0))
    let after = makeImageWithSquare(width: 20, height: 20, background: (255, 255, 255), squareColor: (0, 0, 0), squareRect: (x: 5, y: 5, size: 5))

    let masks = [DOMMask(selector: ".review-count")]
    let liveRects: [String: CGRect] = [".review-count": CGRect(x: 5, y: 5, width: 5, height: 5)]
    let resolution = DOMMaskResolver.resolve(masks, liveRects: liveRects)

    let result = try ImageDiff.pixelDiff(before: before, after: after, ignoredRegions: resolution.regions)
    XCTAssertEqual(result.differingRatio, 0)
  }
}
