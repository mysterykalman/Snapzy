//
//  Region.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureCore module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//
//  A rectangular capture/crop region in a well-defined coordinate space.
//  Coordinate space is a property of the call site (screen points, display
//  pixels, or DOM CSS pixels) -- this type is deliberately just the geometry.
//

import CoreGraphics
import Foundation

struct Region: Codable, Equatable, Sendable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  var cgRect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }

  init(cgRect: CGRect) {
    self.x = cgRect.origin.x
    self.y = cgRect.origin.y
    self.width = cgRect.size.width
    self.height = cgRect.size.height
  }

  /// Normalizes negative width/height produced by a drag that moved
  /// up/left of its starting point into a standard positive-size rect.
  var normalized: Region {
    var r = self
    if r.width < 0 {
      r.x += r.width
      r.width = -r.width
    }
    if r.height < 0 {
      r.y += r.height
      r.height = -r.height
    }
    return r
  }

  var isEmpty: Bool {
    width <= 0 || height <= 0
  }

  /// Grows the region by `padding` on every side (a negative value
  /// shrinks it instead), clamping a shrink large enough to eliminate the
  /// region entirely to a zero-size rect at its own center rather than
  /// going negative.
  func padded(by padding: Double) -> Region {
    let newWidth = max(0, width + padding * 2)
    let newHeight = max(0, height + padding * 2)
    let centerX = x + width / 2
    let centerY = y + height / 2
    return Region(x: centerX - newWidth / 2, y: centerY - newHeight / 2, width: newWidth, height: newHeight)
  }

  /// Clamps this region to fit entirely within `bounds` (e.g. an image's
  /// own pixel dimensions) -- a browser-reported element rect (or one
  /// padding just expanded) can legitimately extend beyond the actual
  /// captured screenshot's edges.
  func clamped(to bounds: Region) -> Region {
    let minX = max(x, bounds.x)
    let minY = max(y, bounds.y)
    let maxX = min(x + width, bounds.x + bounds.width)
    let maxY = min(y + height, bounds.y + bounds.height)
    return Region(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
  }
}
