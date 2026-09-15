//
//  HistoryTextExtracting.swift
//  Snapzy
//

import CoreGraphics
import Foundation

/// Extracts recognizable text from an image, for indexing capture
/// history records for full-text search. Extracted as a protocol (with
/// `VisionHistoryTextExtractor` as the real implementation) so
/// `HistoryOCRIndexer` can be tested without exercising Vision directly
/// -- `SnapzyTests/OCRRecognitionTests` is already CI-skipped for
/// crashing on GitHub Actions macOS runners (see .github/workflows/
/// ci.yml), so real Vision OCR calls are not something to add to the CI
/// test surface here.
protocol HistoryTextExtracting {
  func extractText(from image: CGImage) async throws -> String
}

/// Routes through the existing `OCRService`/Vision pipeline already
/// used for capture-time OCR, rather than standing up a second
/// independent text-recognition path.
struct VisionHistoryTextExtractor: HistoryTextExtracting {
  private let ocrService: OCRService

  init(ocrService: OCRService = .shared) {
    self.ocrService = ocrService
  }

  func extractText(from image: CGImage) async throws -> String {
    let result = try await ocrService.recognize(OCRRequest(image: image))
    return result.text
  }
}
