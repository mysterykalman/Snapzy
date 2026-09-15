//
//  HistoryStoring.swift
//  Snapzy
//

import Combine
import Foundation

/// The slice of `CaptureHistoryStore` that history-search and indexing
/// code depends on, extracted so that code can be tested against a fake
/// store instead of the real GRDB-backed singleton -- the same DI shape
/// `QuickAccessManaging` already establishes for `QuickAccessManager`.
protocol HistoryStoring: AnyObject {
  var records: [CaptureHistoryRecord] { get }
  var recordsPublisher: AnyPublisher<[CaptureHistoryRecord], Never> { get }

  func updateOCRText(id: UUID, text: String?)

  /// Full-text search over file name and OCR text (see
  /// `CaptureHistoryStore.search(query:)` for the real FTS5-backed
  /// implementation). Empty/whitespace-only query returns `[]`.
  func search(query: String) -> [CaptureHistoryRecord]
}

extension CaptureHistoryStore: HistoryStoring {
  var recordsPublisher: AnyPublisher<[CaptureHistoryRecord], Never> {
    $records.eraseToAnyPublisher()
  }
}
