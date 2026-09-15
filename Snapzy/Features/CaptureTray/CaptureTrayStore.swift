//
//  CaptureTrayStore.swift
//  Snapzy
//
//  Spec §2.5 "Multi-Capture and Assembly" names a persistent Capture
//  Tray as a first-class core workflow: capture -> appears in tray ->
//  capture mode stays ready -> repeat -> reorder -> "Assemble" -- and
//  per docs/GAP_AUDIT.md, nothing like it existed anywhere in Snapzy.
//  This store is the tray's persistent backing list: an ordered set of
//  file URLs that survives app relaunch (paths only -- content-
//  addressed dedupe/thumbnails already live in History, so the tray
//  doesn't duplicate that infrastructure, it just references files by
//  path the same way History already does).
//

import Combine
import Foundation

@MainActor
final class CaptureTrayStore: ObservableObject {
  static let shared = CaptureTrayStore()

  @Published private(set) var items: [URL] = []

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let storedPaths = defaults.stringArray(forKey: PreferencesKeys.captureTrayFilePaths) ?? []
    self.items = storedPaths
      .map { URL(fileURLWithPath: $0) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  // Every class implicitly picks up this project's
  // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor build setting; without an
  // explicit deinit the compiler synthesizes an isolated one that hits
  // a Swift runtime bug on deallocation of a non-singleton instance
  // (see DatabaseManager.swift for the full writeup). This type is
  // constructed transiently in its own tests (a fresh store per test,
  // via the `defaults:` initializer), which is exactly that pattern.
  nonisolated deinit {}

  var canAssemble: Bool { items.count >= 2 }

  func add(_ url: URL) {
    guard !items.contains(url) else { return }
    items.append(url)
    persist()
  }

  func remove(_ url: URL) {
    items.removeAll { $0 == url }
    persist()
  }

  func move(fromOffsets: IndexSet, toOffset: Int) {
    items.move(fromOffsets: fromOffsets, toOffset: toOffset)
    persist()
  }

  func clear() {
    items.removeAll()
    persist()
  }

  private func persist() {
    defaults.set(items.map(\.path), forKey: PreferencesKeys.captureTrayFilePaths)
  }
}
