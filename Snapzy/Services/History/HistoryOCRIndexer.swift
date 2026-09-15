//
//  HistoryOCRIndexer.swift
//  Snapzy
//
//  Populates CaptureHistoryRecord.ocrText in the background so history
//  search (HistorySearchViewModel) can match on a screenshot's visible
//  text, not just its file name. Mirrors HistoryThumbnailGenerator's
//  "lazy, best-effort, write back via the store" shape rather than
//  inventing a different background-enrichment pattern for this one
//  new field.
//

import CoreGraphics
import Foundation
import ImageIO

@MainActor
final class HistoryOCRIndexer {
  static let shared = HistoryOCRIndexer(store: CaptureHistoryStore.shared, extractor: VisionHistoryTextExtractor())

  private let store: any HistoryStoring
  private let extractor: HistoryTextExtracting

  init(store: any HistoryStoring, extractor: HistoryTextExtracting) {
    self.store = store
    self.extractor = extractor
  }

  // See DatabaseManager.swift for the full writeup: any class without an
  // explicit deinit implicitly picks up this project's
  // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor setting and gets a
  // compiler-synthesized isolated deinit, which hits a Swift runtime bug
  // when a *transient* (non-singleton) instance is deallocated -- and
  // HistoryOCRIndexerTests constructs exactly that (a fresh instance per
  // test, going out of scope at teardown), so this is not just
  // precautionary insurance the way it is for `.shared`-only types.
  nonisolated deinit {}

  /// Indexes `record` in the background if it's a screenshot that
  /// hasn't been indexed yet. No-op for video/GIF records (OCR-ing
  /// every frame isn't worth the cost for a personal-use history
  /// search) and for records that already have `ocrText` set --
  /// including records OCR previously found no text in, so a blank
  /// screenshot isn't retried forever.
  func indexIfNeeded(_ record: CaptureHistoryRecord) {
    guard record.captureType == .screenshot, record.ocrText == nil else { return }

    let recordID = record.id
    let filePath = record.filePath
    Task {
      guard let image = Self.loadImage(atPath: filePath) else { return }
      guard let text = try? await extractor.extractText(from: image) else { return }
      store.updateOCRText(id: recordID, text: text.isEmpty ? nil : text)
    }
  }

  private static func loadImage(atPath path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}
