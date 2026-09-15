//
//  FakeHistoryStore.swift
//  SnapzyTests
//
//  An in-memory HistoryStoring conformer so history-search/indexing
//  code can be tested without the real GRDB-backed CaptureHistoryStore.
//

import Combine
import Foundation
@testable import Snapzy

@MainActor
final class FakeHistoryStore: HistoryStoring {
  @Published private(set) var records: [CaptureHistoryRecord] = []
  private(set) var updatedOCRText: [(id: UUID, text: String?)] = []

  var recordsPublisher: AnyPublisher<[CaptureHistoryRecord], Never> {
    $records.eraseToAnyPublisher()
  }

  func setRecords(_ records: [CaptureHistoryRecord]) {
    self.records = records
  }

  func updateOCRText(id: UUID, text: String?) {
    updatedOCRText.append((id: id, text: text))
    if let index = records.firstIndex(where: { $0.id == id }) {
      records[index].ocrText = text
    }
  }

  // A fresh instance is constructed per test and goes out of scope at
  // teardown -- exactly the transient-instance pattern that hits the
  // MainActor isolated-deinit runtime bug documented in
  // DatabaseManager.swift. Without this, FakeHistoryStore itself could
  // reintroduce the same crash this session already root-caused twice.
  nonisolated deinit {}
}
