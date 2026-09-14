//
//  ImageDiff.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureDiff module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//
//  Pixel-level visual diff: pixel (exact) and perceptual (block-averaged,
//  reduces anti-alias noise) modes, plus overlay/swipe comparison-view
//  compositing. Baselines, approval states, and the higher-level
//  "compare against previous/named baseline/another viewport" workflow
//  live in Baseline.swift; this file is the actual pixel math those
//  workflows call into.
//

import CoreGraphics
import Foundation

enum ImageDiff {
  enum DiffError: Error, LocalizedError {
    case dimensionMismatch(before: (Int, Int), after: (Int, Int))
    case pixelBufferCreationFailed

    var errorDescription: String? {
      switch self {
      case .dimensionMismatch(let before, let after):
        return "Images must be the same size to diff (before: \(before.0)x\(before.1), after: \(after.0)x\(after.1))."
      case .pixelBufferCreationFailed:
        return "Could not read raw pixel data from an image."
      }
    }
  }

  struct Result {
    /// Same size as the inputs: differing regions are highlighted;
    /// unchanged regions are a dimmed grayscale of `after`, so the diff
    /// is legible in context rather than a bare black-and-white mask.
    var diffImage: CGImage
    /// Fraction (0...1) of the image that differs.
    var differingRatio: Double
  }

  private struct RGBABuffer {
    var pixels: [UInt8]  // 4 bytes per pixel, RGBA
    var width: Int
    var height: Int

    subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
      let offset = (y * width + x) * 4
      return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }
  }

  private static func readRGBA(_ image: CGImage) throws -> RGBABuffer {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw DiffError.pixelBufferCreationFailed
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return RGBABuffer(pixels: pixels, width: width, height: height)
  }

  private static func makeImage(from pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
    var pixels = pixels
    guard
      let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ), let image = context.makeImage()
    else {
      throw DiffError.pixelBufferCreationFailed
    }
    return image
  }

  /// Exact per-pixel comparison -- any RGB difference at all counts.
  /// Useful when even sub-pixel rendering noise matters (e.g.
  /// confirming a build produces byte-identical output); for normal
  /// visual regression checking, `perceptualDiff` is usually the better
  /// default since anti-aliasing alone will otherwise flag as a false
  /// positive on every run. `ignoredRegions` (in pixel coordinates,
  /// top-left origin matching `CGImage`'s own pixel space) implements
  /// noise-suppression "mask selected regions"/"ignore dynamic region"
  /// -- pixels inside any of these rects are still rendered (dimmed,
  /// like any unchanged pixel) but never counted as differing and never
  /// highlighted, so a known-volatile area (a rotating recommendations
  /// carousel, a live timestamp) doesn't produce false-positive diffs.
  static func pixelDiff(before: CGImage, after: CGImage, highlight: (r: UInt8, g: UInt8, b: UInt8) = (255, 0, 0), ignoredRegions: [CGRect] = []) throws -> Result {
    guard before.width == after.width, before.height == after.height else {
      throw DiffError.dimensionMismatch(before: (before.width, before.height), after: (after.width, after.height))
    }
    let beforeBuffer = try readRGBA(before)
    let afterBuffer = try readRGBA(after)
    let width = before.width
    let height = before.height

    var output = [UInt8](repeating: 0, count: width * height * 4)
    var differingCount = 0

    for y in 0..<height {
      for x in 0..<width {
        let b = beforeBuffer[x, y]
        let a = afterBuffer[x, y]
        let offset = (y * width + x) * 4
        let isMasked = ignoredRegions.contains { $0.contains(CGPoint(x: x, y: y)) }
        if !isMasked && (b.r != a.r || b.g != a.g || b.b != a.b) {
          differingCount += 1
          output[offset] = highlight.r
          output[offset + 1] = highlight.g
          output[offset + 2] = highlight.b
          output[offset + 3] = 255
        } else {
          let gray = dimmedGray(a)
          output[offset] = gray
          output[offset + 1] = gray
          output[offset + 2] = gray
          output[offset + 3] = 255
        }
      }
    }

    let diffImage = try makeImage(from: output, width: width, height: height)
    return Result(diffImage: diffImage, differingRatio: Double(differingCount) / Double(width * height))
  }

  /// Block-averaged comparison -- the "perceptual (reduce anti-alias
  /// noise)" mode: divides the image into `blockSize`x`blockSize` tiles,
  /// compares each tile's *average* luminance rather than individual
  /// pixels, and only flags a tile as differing if that average moves
  /// by more than `tolerance` (0...255). This is deliberately coarser
  /// than `pixelDiff` -- a single anti-aliased edge shifting by a
  /// sub-pixel amount changes individual pixels but barely moves a
  /// block's average, so it's naturally tolerant of exactly the kind of
  /// rendering noise this mode targets, without needing a more
  /// elaborate perceptual-hash/SSIM implementation.
  static func perceptualDiff(before: CGImage, after: CGImage, blockSize: Int = 8, tolerance: Double = 12) throws -> Result {
    guard before.width == after.width, before.height == after.height else {
      throw DiffError.dimensionMismatch(before: (before.width, before.height), after: (after.width, after.height))
    }
    let beforeBuffer = try readRGBA(before)
    let afterBuffer = try readRGBA(after)
    let width = before.width
    let height = before.height

    var output = [UInt8](repeating: 0, count: width * height * 4)
    var differingPixelCount = 0

    var blockY = 0
    while blockY < height {
      let blockHeight = min(blockSize, height - blockY)
      var blockX = 0
      while blockX < width {
        let blockWidth = min(blockSize, width - blockX)
        let beforeLuma = averageLuminance(beforeBuffer, x0: blockX, y0: blockY, w: blockWidth, h: blockHeight)
        let afterLuma = averageLuminance(afterBuffer, x0: blockX, y0: blockY, w: blockWidth, h: blockHeight)
        let differs = abs(beforeLuma - afterLuma) > tolerance

        for y in blockY..<(blockY + blockHeight) {
          for x in blockX..<(blockX + blockWidth) {
            let offset = (y * width + x) * 4
            if differs {
              differingPixelCount += 1
              output[offset] = 255
              output[offset + 1] = 0
              output[offset + 2] = 0
              output[offset + 3] = 255
            } else {
              let gray = dimmedGray(afterBuffer[x, y])
              output[offset] = gray
              output[offset + 1] = gray
              output[offset + 2] = gray
              output[offset + 3] = 255
            }
          }
        }
        blockX += blockSize
      }
      blockY += blockSize
    }

    let diffImage = try makeImage(from: output, width: width, height: height)
    return Result(diffImage: diffImage, differingRatio: Double(differingPixelCount) / Double(width * height))
  }

  /// Alpha-blends `after` over `before` at `opacity` (0...1) -- the
  /// "overlay" / "opacity slider" comparison view.
  static func overlay(before: CGImage, after: CGImage, opacity: Double) throws -> CGImage {
    guard before.width == after.width, before.height == after.height else {
      throw DiffError.dimensionMismatch(before: (before.width, before.height), after: (after.width, after.height))
    }
    let width = before.width
    let height = before.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw DiffError.pixelBufferCreationFailed
    }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.draw(before, in: rect)
    context.setAlpha(CGFloat(max(0, min(1, opacity))))
    context.draw(after, in: rect)
    guard let image = context.makeImage() else { throw DiffError.pixelBufferCreationFailed }
    return image
  }

  /// Composites `before` on the left of `dividerFraction` (0...1) and
  /// `after` on the right -- the "swipe" comparison view (the
  /// draggable-divider UI itself is a separate editor-UI concern; this
  /// is just the pixel compositing for a given divider position).
  static func swipe(before: CGImage, after: CGImage, dividerFraction: Double) throws -> CGImage {
    guard before.width == after.width, before.height == after.height else {
      throw DiffError.dimensionMismatch(before: (before.width, before.height), after: (after.width, after.height))
    }
    let width = before.width
    let height = before.height
    let dividerX = Int((max(0, min(1, dividerFraction)) * Double(width)).rounded())

    let beforeBuffer = try readRGBA(before)
    let afterBuffer = try readRGBA(after)
    var output = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let source = x < dividerX ? beforeBuffer : afterBuffer
        let pixel = source[x, y]
        let offset = (y * width + x) * 4
        output[offset] = pixel.r
        output[offset + 1] = pixel.g
        output[offset + 2] = pixel.b
        output[offset + 3] = pixel.a
      }
    }
    return try makeImage(from: output, width: width, height: height)
  }

  private static func dimmedGray(_ pixel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> UInt8 {
    let luma = 0.299 * Double(pixel.r) + 0.587 * Double(pixel.g) + 0.114 * Double(pixel.b)
    return UInt8(max(0, min(255, luma * 0.5)))
  }

  private static func averageLuminance(_ buffer: RGBABuffer, x0: Int, y0: Int, w: Int, h: Int) -> Double {
    var total = 0.0
    for y in y0..<(y0 + h) {
      for x in x0..<(x0 + w) {
        let pixel = buffer[x, y]
        total += 0.299 * Double(pixel.r) + 0.587 * Double(pixel.g) + 0.114 * Double(pixel.b)
      }
    }
    return total / Double(w * h)
  }
}
