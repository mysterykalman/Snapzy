//
//  PDFRedactor.swift
//  Snapzy
//
//  Ported from the original Capture app's CapturePDF module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//

import CoreGraphics
import Foundation

/// A solid black box drawn *on top* of PDF text leaves the original text
/// fully intact and extractable underneath — copy/paste or a text-
/// extraction tool recovers it completely, a real, well-known failure
/// mode of naive "visual" PDF redaction. Genuine permanence requires
/// actually removing the underlying text content, not just obscuring it
/// visually.
///
/// This achieves real permanence the honest way available without a PDF
/// content-stream editor: the *targeted* page is fully rasterized
/// (rendered to a bitmap with the redaction box drawn in, then that
/// bitmap — not the original vector page — becomes the new page's only
/// content), so there is no text layer left on that page at all for
/// anything to extract, redacted or not. Every *other* page is
/// re-embedded as real vector content via `CGContext.drawPDFPage` into
/// the new PDF context so non-redacted pages keep their real searchable/
/// selectable text rather than being flattened unnecessarily.
enum PDFRedactor {
  enum RedactError: Error, LocalizedError {
    case documentLoadFailed
    case invalidPageIndex
    case contextCreationFailed

    var errorDescription: String? {
      switch self {
      case .documentLoadFailed: return "Could not load the source PDF."
      case .invalidPageIndex: return "The requested page index is out of range."
      case .contextCreationFailed: return "Could not create a PDF rendering context."
      }
    }
  }

  /// `pageIndex` is 1-based, matching `CGPDFDocument.page(at:)`'s own
  /// convention. `region`/`fillColor` are in the target page's own PDF
  /// coordinate space (bottom-left origin). `scale` controls the
  /// rasterization resolution (2 = retina-equivalent) — higher preserves
  /// more visual fidelity for the now-flattened page's non-redacted
  /// content.
  static func redactPage(
    pdfAt inputURL: URL, pageIndex: Int, region: CGRect,
    fillColor: CGColor = CGColor(gray: 0, alpha: 1), scale: CGFloat = 2,
    to outputURL: URL
  ) throws {
    guard let document = CGPDFDocument(inputURL as CFURL) else { throw RedactError.documentLoadFailed }
    let pageCount = document.numberOfPages
    guard pageIndex >= 1, pageIndex <= pageCount, let targetPage = document.page(at: pageIndex) else {
      throw RedactError.invalidPageIndex
    }

    let redactedImage = try rasterizeWithRedaction(page: targetPage, region: region, fillColor: fillColor, scale: scale)

    guard let consumer = CGDataConsumer(url: outputURL as CFURL) else { throw RedactError.contextCreationFailed }
    var initialMediaBox = targetPage.getBoxRect(.mediaBox)
    guard let outputContext = CGContext(consumer: consumer, mediaBox: &initialMediaBox, nil) else {
      throw RedactError.contextCreationFailed
    }

    for index in 1...pageCount {
      guard let page = document.page(at: index) else { continue }
      var pageBox = page.getBoxRect(.mediaBox)
      outputContext.beginPage(mediaBox: &pageBox)
      if index == pageIndex {
        // The rasterized replacement — no vector text survives on this
        // page at all.
        outputContext.draw(redactedImage, in: pageBox)
      } else {
        // Real vector re-embedding, not a rasterize-everything shortcut
        // — every other page keeps its own real searchable/selectable
        // text untouched.
        outputContext.drawPDFPage(page)
      }
      outputContext.endPage()
    }
    outputContext.closePDF()
  }

  private static func rasterizeWithRedaction(page: CGPDFPage, region: CGRect, fillColor: CGColor, scale: CGFloat) throws -> CGImage {
    let box = page.getBoxRect(.mediaBox)
    let pixelWidth = max(1, Int((box.width * scale).rounded()))
    let pixelHeight = max(1, Int((box.height * scale).rounded()))
    guard
      let context = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw RedactError.contextCreationFailed
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    context.scaleBy(x: scale, y: scale)
    context.drawPDFPage(page)

    context.setFillColor(fillColor)
    context.fill(region)

    guard let image = context.makeImage() else { throw RedactError.contextCreationFailed }
    return image
  }
}
