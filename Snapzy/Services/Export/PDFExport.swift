//
//  PDFExport.swift
//  Snapzy
//
//  Ported from the original Capture app's CapturePDF module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//

import CoreGraphics
import Foundation
import ImageIO

/// PDF export via CoreGraphics — `CGContext`'s built-in PDF consumer is
/// the lighter system-framework path when the only requirement is
/// "render N images as N PDF pages," not general PDF document editing.
enum PDFExport {
  enum ExportError: Error, LocalizedError {
    case contextCreationFailed
    case emptyImageList

    var errorDescription: String? {
      switch self {
      case .contextCreationFailed: return "Could not create a PDF rendering context."
      case .emptyImageList: return "No images were provided to export."
      }
    }
  }

  /// Renders `images` as one PDF page per image, each page sized to that
  /// image's pixel dimensions ("multiple screenshots as pages, long
  /// scrolling capture split into pages").
  static func write(images: [CGImage], to url: URL) throws {
    try write(images: images, to: url, userPassword: nil, ownerPassword: nil, allowsPrinting: true, allowsCopying: true)
  }

  /// Real PDF encryption via `CGContext`'s own auxiliary-info dictionary
  /// (the same mechanism Preview.app/Adobe Acrobat use), not a hand-
  /// rolled scheme. `userPassword` (nil = no password required to *open*
  /// the document) and `ownerPassword` (nil = no separate password
  /// required to change permissions) are independent in the PDF format's
  /// own encryption model, but `CGContext` only actually turns on real
  /// encryption when an owner password is present at all — setting only
  /// a user password silently produces an *unencrypted* PDF. So a
  /// `userPassword` with no explicit `ownerPassword` defaults the owner
  /// password to the same value, which reliably does turn encryption on.
  /// `allowsPrinting`/`allowsCopying` are only meaningfully enforced by a
  /// compliant reader when an owner password is set.
  static func write(
    images: [CGImage], to url: URL,
    userPassword: String?, ownerPassword: String?,
    allowsPrinting: Bool = true, allowsCopying: Bool = true
  ) throws {
    guard !images.isEmpty else { throw ExportError.emptyImageList }
    guard let consumer = CGDataConsumer(url: url as CFURL) else {
      throw ExportError.contextCreationFailed
    }

    let effectiveOwnerPassword = ownerPassword ?? userPassword

    var auxiliaryInfo: [CFString: Any] = [:]
    if let userPassword { auxiliaryInfo[kCGPDFContextUserPassword] = userPassword }
    if let effectiveOwnerPassword { auxiliaryInfo[kCGPDFContextOwnerPassword] = effectiveOwnerPassword }
    if userPassword != nil || effectiveOwnerPassword != nil {
      auxiliaryInfo[kCGPDFContextAllowsPrinting] = allowsPrinting
      auxiliaryInfo[kCGPDFContextAllowsCopying] = allowsCopying
    }

    var mediaBox = CGRect(x: 0, y: 0, width: images[0].width, height: images[0].height)
    guard
      let context = CGContext(
        consumer: consumer, mediaBox: &mediaBox,
        auxiliaryInfo.isEmpty ? nil : auxiliaryInfo as CFDictionary
      )
    else {
      throw ExportError.contextCreationFailed
    }

    for image in images {
      var pageBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
      context.beginPage(mediaBox: &pageBox)
      context.draw(image, in: pageBox)
      context.endPage()
    }
    context.closePDF()
  }

  /// Slices one very tall `tallImage` into `pageHeight`-tall horizontal
  /// strips (the last strip is whatever remains, not padded/stretched to
  /// a full page) and writes each strip as its own PDF page — cropping
  /// one strip at a time via `CGImage.cropping(to:)` (a lightweight,
  /// source-backed view, not a full re-decode of the whole image) rather
  /// than ever holding every strip's fully-decoded pixels in memory at
  /// once. Use for exporting a long scrolling-capture session as a
  /// paginated PDF.
  static func writeSplitIntoPages(
    tallImage: CGImage, pageHeight: Int, to url: URL,
    userPassword: String? = nil, ownerPassword: String? = nil,
    allowsPrinting: Bool = true, allowsCopying: Bool = true
  ) throws {
    guard pageHeight > 0 else { throw ExportError.emptyImageList }
    let width = tallImage.width
    let totalHeight = tallImage.height
    var pages: [CGImage] = []
    var y = 0
    while y < totalHeight {
      let sliceHeight = min(pageHeight, totalHeight - y)
      guard let slice = tallImage.cropping(to: CGRect(x: 0, y: y, width: width, height: sliceHeight)) else { break }
      pages.append(slice)
      y += sliceHeight
    }
    try write(images: pages, to: url, userPassword: userPassword, ownerPassword: ownerPassword, allowsPrinting: allowsPrinting, allowsCopying: allowsCopying)
  }
}
