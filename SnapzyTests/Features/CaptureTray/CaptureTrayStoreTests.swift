//
//  CaptureTrayStoreTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

@MainActor
final class CaptureTrayStoreTests: XCTestCase {

  private var testDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    testDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_CaptureTray_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let testDirectory {
      try? FileManager.default.removeItem(at: testDirectory)
    }
    try super.tearDownWithError()
  }

  private func makeTestDefaults(file: StaticString = #file, line: UInt = #line) throws -> UserDefaults {
    let suiteName = "CaptureTrayStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName), file: file, line: line)
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  /// A real file on disk -- `CaptureTrayStore`'s init filters out
  /// stored paths whose file no longer exists, so a fixture file needs
  /// to genuinely be there for persistence-round-trip tests.
  private func makeFixtureFile(named name: String) -> URL {
    let url = testDirectory.appendingPathComponent(name)
    try? Data("fixture".utf8).write(to: url)
    return url
  }

  func testAddAppendsANewItem() throws {
    let store = CaptureTrayStore(defaults: try makeTestDefaults())
    let url = makeFixtureFile(named: "one.png")

    store.add(url)

    XCTAssertEqual(store.items, [url])
  }

  func testAddIgnoresADuplicateURL() throws {
    let store = CaptureTrayStore(defaults: try makeTestDefaults())
    let url = makeFixtureFile(named: "one.png")

    store.add(url)
    store.add(url)

    XCTAssertEqual(store.items, [url])
  }

  func testRemoveDeletesJustThatItem() throws {
    let store = CaptureTrayStore(defaults: try makeTestDefaults())
    let first = makeFixtureFile(named: "one.png")
    let second = makeFixtureFile(named: "two.png")
    store.add(first)
    store.add(second)

    store.remove(first)

    XCTAssertEqual(store.items, [second])
  }

  func testMoveReordersItems() throws {
    let store = CaptureTrayStore(defaults: try makeTestDefaults())
    let first = makeFixtureFile(named: "one.png")
    let second = makeFixtureFile(named: "two.png")
    let third = makeFixtureFile(named: "three.png")
    store.add(first)
    store.add(second)
    store.add(third)

    store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)

    XCTAssertEqual(store.items, [second, third, first])
  }

  func testClearRemovesEverything() throws {
    let store = CaptureTrayStore(defaults: try makeTestDefaults())
    store.add(makeFixtureFile(named: "one.png"))
    store.add(makeFixtureFile(named: "two.png"))

    store.clear()

    XCTAssertTrue(store.items.isEmpty)
  }

  func testCanAssembleRequiresAtLeastTwoItems() throws {
    let store = CaptureTrayStore(defaults: try makeTestDefaults())
    XCTAssertFalse(store.canAssemble)

    store.add(makeFixtureFile(named: "one.png"))
    XCTAssertFalse(store.canAssemble)

    store.add(makeFixtureFile(named: "two.png"))
    XCTAssertTrue(store.canAssemble)
  }

  func testItemsPersistAcrossStoreInstancesSharingTheSameDefaults() throws {
    let defaults = try makeTestDefaults()
    let first = makeFixtureFile(named: "one.png")
    let second = makeFixtureFile(named: "two.png")

    let store1 = CaptureTrayStore(defaults: defaults)
    store1.add(first)
    store1.add(second)

    let store2 = CaptureTrayStore(defaults: defaults)
    XCTAssertEqual(store2.items, [first, second])
  }

  func testInitFiltersOutPathsWhoseFileNoLongerExists() throws {
    let defaults = try makeTestDefaults()
    let stillThere = makeFixtureFile(named: "still-there.png")
    let deleted = testDirectory.appendingPathComponent("deleted.png")
    try Data("temp".utf8).write(to: deleted)

    let store1 = CaptureTrayStore(defaults: defaults)
    store1.add(stillThere)
    store1.add(deleted)
    try FileManager.default.removeItem(at: deleted)

    let store2 = CaptureTrayStore(defaults: defaults)
    XCTAssertEqual(store2.items, [stillThere])
  }
}
