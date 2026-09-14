//
//  ClientSafeExportPreparer.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureVision module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md), adapted to call Snapzy's
//  own mature OCR pipeline (`OCRService`) rather than porting a second,
//  redundant text recognizer.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The "client-safe export" preset: strip metadata + run a sensitive-data
/// scan over the image's own visible text. A real coordinator over
/// already-independently-implemented pieces rather than new detection
/// logic. "Flatten redactions" and "exclude raw project data" are the
/// caller's own responsibility before calling this: by the time a
/// flattened `CGImage` reaches here, any redactions are already baked in.
@MainActor
enum ClientSafeExportPreparer {
  struct Result {
    /// The real, metadata-stripped output bytes, ready to leave the
    /// machine.
    var strippedImageData: Data
    /// Real `PrivacyPreflight` matches found in the image's own OCR'd
    /// text, surfaced so a caller can show "N sensitive items found"
    /// before actually sharing. This function itself never blocks
    /// export on a non-empty scan — that decision is the caller's.
    var privacyMatches: [PrivacyPreflight.Match]
  }

  enum PrepareError: Error, LocalizedError {
    case encodingFailed

    var errorDescription: String? {
      "Could not encode the image before scanning it for sensitive text."
    }
  }

  /// `flattenedImage` must already have redactions baked in (a caller's
  /// job before calling this, not repeated here). `confidentialTerms` is
  /// passed straight through to `PrivacyPreflight.scan`.
  static func prepare(
    flattenedImage: CGImage, outputType: UTType = .png, confidentialTerms: [String] = []
  ) async throws -> Result {
    let recognizedText = try await OCRService.shared.recognizeText(from: flattenedImage)
    let matches = PrivacyPreflight.scan(recognizedText, confidentialTerms: confidentialTerms)

    let rawData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(rawData, UTType.png.identifier as CFString, 1, nil) else {
      throw PrepareError.encodingFailed
    }
    CGImageDestinationAddImage(destination, flattenedImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw PrepareError.encodingFailed
    }

    let strippedData = try MetadataStripper.stripMetadata(from: rawData as Data, outputType: outputType)
    return Result(strippedImageData: strippedData, privacyMatches: matches)
  }
}
