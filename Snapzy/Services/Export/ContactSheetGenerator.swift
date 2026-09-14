//
//  ContactSheetGenerator.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureCore module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md), adapted to use Snapzy's
//  existing `SnapzyConfigurationColor` hex parser rather than porting a
//  second one.
//

import AppKit
import CoreGraphics
import CoreText

/// Pure CoreGraphics/CoreText compositing of already-captured images into
/// one larger image — no capture/editor-document involvement, so it works
/// over any set of `CGImage`s a caller already has (recent History
/// captures, a responsive multi-viewport set, etc.).
enum ContactSheetGenerator {
  enum Layout: Equatable {
    /// Wraps into rows of `columns` images each.
    case grid(columns: Int)
    /// A single column, one image per row.
    case verticalStack
    /// A single row, side by side (e.g. several viewport widths compared
    /// left to right).
    case horizontalStack
  }

  /// Every image is placed in a uniformly-sized cell (the largest width/
  /// height among all input images), centered within it — images of
  /// different sizes (e.g. different capture dimensions) don't distort
  /// the layout or get stretched. Returns `nil` for an empty `images`
  /// array (nothing to compose) or if the backing bitmap context can't
  /// be created.
  ///
  /// - Parameters:
  ///   - labels: one label per image, drawn in its own strip below the
  ///     image. Must match `images.count` to take effect at all; a
  ///     mismatched or `nil` array means no labels are drawn (and no
  ///     space reserved for them), rather than guessing which images to
  ///     label.
  static func generate(
    images: [CGImage], layout: Layout, spacing: CGFloat = 12,
    labels: [String]? = nil, labelHeight: CGFloat = 24, backgroundColorHex: String = "#FFFFFF"
  ) -> CGImage? {
    guard !images.isEmpty else { return nil }

    let cellWidth = images.map { CGFloat($0.width) }.max() ?? 0
    let cellHeight = images.map { CGFloat($0.height) }.max() ?? 0
    let hasLabels = labels?.count == images.count
    let cellTotalHeight = cellHeight + (hasLabels ? labelHeight : 0)

    let columns: Int
    let rows: Int
    switch layout {
    case .grid(let requestedColumns):
      columns = max(1, requestedColumns)
      rows = Int((Double(images.count) / Double(columns)).rounded(.up))
    case .verticalStack:
      columns = 1
      rows = images.count
    case .horizontalStack:
      columns = images.count
      rows = 1
    }

    let totalWidth = CGFloat(columns) * cellWidth + CGFloat(columns + 1) * spacing
    let totalHeight = CGFloat(rows) * cellTotalHeight + CGFloat(rows + 1) * spacing
    guard totalWidth > 0, totalHeight > 0 else { return nil }

    guard
      let context = CGContext(
        data: nil, width: Int(totalWidth.rounded(.up)), height: Int(totalHeight.rounded(.up)),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    let backgroundColor = SnapzyConfigurationColor.color(from: backgroundColorHex)?.cgColor ?? CGColor(gray: 1, alpha: 1)
    context.setFillColor(backgroundColor)
    context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

    for (index, image) in images.enumerated() {
      let column = index % columns
      let row = index / columns

      let cellX = spacing + CGFloat(column) * (cellWidth + spacing)
      // Row 0 belongs at the *top* of the composed image. A CGImage's
      // own data is top-down, but this bitmap context's coordinate
      // space is bottom-left/y-up, so the top of the final image
      // corresponds to the *highest* y in this context — row 0 gets the
      // largest y, later rows progressively smaller.
      let cellYFromTop = spacing + CGFloat(row) * (cellTotalHeight + spacing)
      let cellY = totalHeight - cellYFromTop - cellTotalHeight

      let imageWidth = CGFloat(image.width)
      let imageHeight = CGFloat(image.height)
      let imageOrigin = CGPoint(
        x: cellX + (cellWidth - imageWidth) / 2,
        y: cellY + (hasLabels ? labelHeight : 0) + (cellHeight - imageHeight) / 2
      )
      context.draw(image, in: CGRect(origin: imageOrigin, size: CGSize(width: imageWidth, height: imageHeight)))

      if hasLabels, let label = labels?[index] {
        drawLabel(label, in: CGRect(x: cellX, y: cellY, width: cellWidth, height: labelHeight), context: context)
      }
    }

    return context.makeImage()
  }

  /// Same bottom-left-origin-vs-top-left-authored flip technique needed
  /// anywhere CoreText draws into a y-up bitmap context.
  private static func drawLabel(_ text: String, in frame: CGRect, context: CGContext) {
    guard
      let attributed = CFAttributedStringCreate(
        nil, text as CFString, [kCTForegroundColorAttributeName: CGColor(gray: 0.2, alpha: 1)] as CFDictionary
      )
    else { return }
    let line = CTLineCreateWithAttributedString(attributed)

    context.saveGState()
    context.textMatrix = .identity
    context.translateBy(x: frame.minX + 4, y: frame.maxY)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = CGPoint(x: 0, y: frame.height * 0.3)
    CTLineDraw(line, context)
    context.restoreGState()
  }
}
