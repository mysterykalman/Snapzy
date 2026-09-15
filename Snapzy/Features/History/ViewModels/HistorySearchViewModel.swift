//
//  HistorySearchViewModel.swift
//  Snapzy
//
//  Reactive debounced search and background filtering for capture history
//

import Combine
import Foundation

@MainActor
final class HistorySearchViewModel: ObservableObject {
  @Published var searchText: String = ""
  @Published var selectedFilter: CaptureHistoryType? = nil
  @Published var selectedTimeFilter: HistoryFloatingTimeFilter = .all
  @Published private(set) var filteredRecords: [CaptureHistoryRecord] = []

  private let store: any HistoryStoring
  private var cancellables = Set<AnyCancellable>()

  init(
    store: any HistoryStoring = CaptureHistoryStore.shared,
    searchTextPublisher: AnyPublisher<String, Never>? = nil,
    selectedFilterPublisher: AnyPublisher<CaptureHistoryType?, Never>? = nil,
    selectedTimeFilterPublisher: AnyPublisher<HistoryFloatingTimeFilter, Never>? = nil
  ) {
    self.store = store
    let textSource = searchTextPublisher ?? $searchText.eraseToAnyPublisher()
    let filterSource = selectedFilterPublisher ?? $selectedFilter.eraseToAnyPublisher()
    let timeSource = selectedTimeFilterPublisher ?? $selectedTimeFilter.eraseToAnyPublisher()

    Publishers.CombineLatest4(
      store.recordsPublisher,
      textSource
        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .removeDuplicates(),
      filterSource,
      timeSource
    )
    // Stays on Main (unlike the in-memory-substring-scan version this
    // replaced): `store.search(query:)` is a MainActor-isolated method
    // (real SQLite FTS5 query -- see CaptureHistoryStore.search),
    // fast enough not to need a background hop, and calling a
    // MainActor method from a background queue would be an actor-
    // isolation violation.
    .map { [weak store] records, searchText, selectedFilter, selectedTimeFilter -> [CaptureHistoryRecord] in
      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      let now = Date()
      let candidates = query.isEmpty ? records : (store?.search(query: query) ?? [])

      return candidates.filter { record in
        let matchesType = selectedFilter == nil || record.captureType == selectedFilter
        let matchesTime = selectedTimeFilter == .all || selectedTimeFilter.includes(record.capturedAt, relativeTo: now)
        return matchesType && matchesTime
      }
    }
    .sink { [weak self] filtered in
      self?.filteredRecords = filtered
    }
    .store(in: &cancellables)
  }

  // Without this, this class's compiler-synthesized isolated deinit
  // (from this project's SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
  // setting) hits the same Swift runtime bug documented in
  // DatabaseManager.swift when a transient instance is deallocated --
  // which HistorySearchViewModelTests does for the first time this
  // class has ever been constructed outside of a long-lived,
  // view-bound context.
  nonisolated deinit {}
}
