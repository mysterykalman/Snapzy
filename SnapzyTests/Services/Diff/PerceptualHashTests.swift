//
//  PerceptualHashTests.swift
//  SnapzyTests
//
//  Ported from the original Capture app's CaptureDiffTests (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md), converted from Swift
//  Testing (@Test/#expect) to this project's XCTest convention.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class PerceptualHashTests: XCTestCase {

  /// Draws a simple, recognizable scene (a light background with a
  /// dark square in one corner) at `size`x`size`, optionally with
  /// `noise` (a small per-pixel brightness jitter) -- real enough
  /// structure that a perceptual hash should treat "the same scene at a
  /// different size" or "the same scene with light noise" as similar,
  /// and "a completely different scene" as dissimilar.
  private func makeSceneImage(size: Int, squareColor: UInt8 = 20, backgroundColor: UInt8 = 220, noiseSeed: UInt32? = nil) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: size * size)
    var rngState = noiseSeed ?? 0
    func nextNoise() -> Int {
      guard noiseSeed != nil else { return 0 }
      rngState = rngState &* 1664525 &+ 1013904223
      return Int(rngState % 11) - 5  // -5...5
    }
    let squareExtent = size / 3
    for y in 0..<size {
      for x in 0..<size {
        let inSquare = x < squareExtent && y < squareExtent
        let base = inSquare ? squareColor : backgroundColor
        let noisy = max(0, min(255, Int(base) + nextNoise()))
        pixels[y * size + x] = UInt8(noisy)
      }
    }
    let context = CGContext(
      data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    return context.makeImage()!
  }

  private func makeInvertedSceneImage(size: Int) -> CGImage {
    // Dark background with a light square -- the visual inverse, a
    // genuinely different-looking image.
    makeSceneImage(size: size, squareColor: 220, backgroundColor: 20)
  }

  func testIdenticalImagesHaveZeroHammingDistance() throws {
    let image = makeSceneImage(size: 64)
    let hashA = try PerceptualHash.averageHash(of: image)
    let hashB = try PerceptualHash.averageHash(of: image)
    XCTAssertEqual(PerceptualHash.hammingDistance(hashA, hashB), 0)
  }

  func testTheSameSceneAtADifferentSizeHashesNearlyIdentically() throws {
    // Real proof of the "resize" robustness aHash is supposed to give --
    // not just "same image twice."
    let small = makeSceneImage(size: 32)
    let large = makeSceneImage(size: 512)
    let hashSmall = try PerceptualHash.averageHash(of: small)
    let hashLarge = try PerceptualHash.averageHash(of: large)
    XCTAssertLessThanOrEqual(PerceptualHash.hammingDistance(hashSmall, hashLarge), 2)
  }

  func testTheSameSceneWithLightNoiseHashesNearlyIdentically() throws {
    let clean = makeSceneImage(size: 64)
    let noisy = makeSceneImage(size: 64, noiseSeed: 42)
    let hashClean = try PerceptualHash.averageHash(of: clean)
    let hashNoisy = try PerceptualHash.averageHash(of: noisy)
    XCTAssertLessThanOrEqual(PerceptualHash.hammingDistance(hashClean, hashNoisy), 6)
  }

  func testAVisuallyDifferentImageHashesFarApart() throws {
    let scene = makeSceneImage(size: 64)
    let inverted = makeInvertedSceneImage(size: 64)
    let hashScene = try PerceptualHash.averageHash(of: scene)
    let hashInverted = try PerceptualHash.averageHash(of: inverted)
    // Should be far more different than the noisy/resized near-duplicate
    // cases above -- a real, meaningful separation, not just "greater
    // than zero."
    XCTAssertGreaterThan(PerceptualHash.hammingDistance(hashScene, hashInverted), 20)
  }

  func testHammingDistanceIsSymmetric() throws {
    let a = try PerceptualHash.averageHash(of: makeSceneImage(size: 64))
    let b = try PerceptualHash.averageHash(of: makeInvertedSceneImage(size: 64))
    XCTAssertEqual(PerceptualHash.hammingDistance(a, b), PerceptualHash.hammingDistance(b, a))
  }
}
