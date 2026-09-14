//
//  PerceptualHash.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureDiff module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//
//  Local visual-similarity search ("find screenshots that look like
//  this"). A classic average hash (aHash): downsample to 8x8 grayscale,
//  threshold each pixel against the block's own mean brightness, pack
//  the 64 resulting bits into a UInt64. Two images that look visually
//  similar (a resize, a minor recompression, a small color/contrast
//  tweak) produce hashes that differ in only a few bits -- genuinely
//  different images produce hashes that differ in roughly half their
//  bits -- so similarity search is just a Hamming-distance threshold
//  over these hashes, no image data needs to be kept in memory or
//  compared pixel by pixel at search time. This is the missing piece
//  for History's "find similar" gap identified during this session's
//  audit of Snapzy's existing history/search architecture.
//

import CoreGraphics
import Foundation

enum PerceptualHash {
  enum HashError: Error, LocalizedError {
    case pixelBufferCreationFailed
    var errorDescription: String? { "Could not read pixel data to compute a hash." }
  }

  private static let gridSize = 8

  /// Computes the 64-bit average hash of `image`. Deliberately ignores
  /// the image's actual aspect ratio (always resamples to a square 8x8
  /// grid) -- aHash is a similarity fingerprint, not a faithful
  /// thumbnail, and forcing a fixed small grid is what keeps the hash
  /// both fast to compute and a fixed, comparable size regardless of the
  /// source image's dimensions.
  static func averageHash(of image: CGImage) throws -> UInt64 {
    var pixels = [UInt8](repeating: 0, count: gridSize * gridSize)
    guard
      let context = CGContext(
        data: &pixels,
        width: gridSize,
        height: gridSize,
        bitsPerComponent: 8,
        bytesPerRow: gridSize,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else {
      throw HashError.pixelBufferCreationFailed
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

    let mean = Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count)

    var hash: UInt64 = 0
    for (index, pixel) in pixels.enumerated() {
      if Double(pixel) >= mean {
        hash |= (1 << UInt64(index))
      }
    }
    return hash
  }

  /// Number of differing bits between two hashes -- 0 means identical
  /// (or so visually similar the 8x8/threshold grid can't tell them
  /// apart), up to 64 means maximally different. A commonly-used
  /// practical similarity threshold is "distance <= ~10" for "looks like
  /// the same or a near-duplicate image," but callers choose their own
  /// threshold rather than this type imposing one.
  static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
    (a ^ b).nonzeroBitCount
  }
}
