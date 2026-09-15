//
//  HistorySearchViewModelTests.swift
//  SnapzyTests
//

import Combine
import XCTest
@testable import Snapzy

@MainActor
final class HistorySearchViewModelTests: XCTestCase {

  private func makeRecord(fileName: String, ocrText: String? = nil) -> CaptureHistoryRecord {
    var record = CaptureHistoryRecord(
      id: UUID(),
      filePath: "/tmp/\(fileName)",
      fileName: fileName,
      captureType: .screenshot,
      fileSize: 1024,
      capturedAt: Date(),
      width: 100,
      height: 100,
      duration: nil,
      thumbnailPath: nil,
      isDeleted: false
    )
    record.ocrText = ocrText
    return record
  }

  private func waitForFilteredRecords(
    _ viewModel: HistorySearchViewModel,
    matching predicate: @escaping ([CaptureHistoryRecord]) -> Bool,
    timeout: TimeInterval = 2
  ) {
    let expectation = expectation(description: "filteredRecords matches")
    var cancellable: AnyCancellable?
    cancellable = viewModel.$filteredRecords
      .sink { records in
        if predicate(records) {
          expectation.fulfill()
        }
      }
    wait(for: [expectation], timeout: timeout)
    cancellable?.cancel()
  }

  func testSearchMatchesFileNameEvenWithoutOCRText() {
    let store = FakeHistoryStore()
    store.setRecords([makeRecord(fileName: "invoice-march.png")])
    let viewModel = HistorySearchViewModel(store: store)

    // Confirm the record is present unfiltered first, so a later empty
    // result can only mean the search predicate genuinely excluded it.
    waitForFilteredRecords(viewModel) { $0.count == 1 }

    viewModel.searchText = "invoice"
    waitForFilteredRecords(viewModel) { $0.count == 1 }
  }

  func testSearchMatchesOCRTextWhenFileNameDoesNotMatch() {
    let store = FakeHistoryStore()
    store.setRecords([makeRecord(fileName: "Screenshot 2026-01-01.png", ocrText: "Total due: $42.00")])
    let viewModel = HistorySearchViewModel(store: store)

    waitForFilteredRecords(viewModel) { $0.count == 1 }

    viewModel.searchText = "total due"
    waitForFilteredRecords(viewModel) { $0.count == 1 }
  }

  func testSearchExcludesRecordsMatchingNeitherFileNameNorOCRText() {
    let store = FakeHistoryStore()
    store.setRecords([makeRecord(fileName: "Screenshot 2026-01-01.png", ocrText: "Unrelated content")])
    let viewModel = HistorySearchViewModel(store: store)

    // First confirm the record starts out present (unfiltered), so the
    // subsequent empty result actually demonstrates exclusion rather
    // than an initial/default empty state.
    waitForFilteredRecords(viewModel) { $0.count == 1 }

    viewModel.searchText = "invoice"
    waitForFilteredRecords(viewModel) { $0.isEmpty }
  }
}
