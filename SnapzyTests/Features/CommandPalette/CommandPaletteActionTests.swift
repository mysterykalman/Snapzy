//
//  CommandPaletteActionTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class CommandPaletteActionTests: XCTestCase {

  func testEmptyQueryReturnsTheFullCatalogInItsDefaultOrder() {
    let results = CommandPaletteAction.matching("")
    XCTAssertEqual(results.map(\.id), CommandPaletteAction.all.map(\.id))
    XCTAssertFalse(results.isEmpty)
  }

  func testWhitespaceOnlyQueryIsTreatedAsEmpty() {
    XCTAssertEqual(CommandPaletteAction.matching("   ").count, CommandPaletteAction.all.count)
  }

  func testMatchIsCaseInsensitiveSubstring() {
    let results = CommandPaletteAction.matching("area")
    XCTAssertTrue(results.contains { $0.id == "captureArea" })
    XCTAssertTrue(results.contains { $0.id == "captureRepeatArea" })
    XCTAssertTrue(results.allSatisfy { $0.title.localizedCaseInsensitiveContains("area") })
  }

  func testNoMatchReturnsAnEmptyList() {
    XCTAssertTrue(CommandPaletteAction.matching("xyz-nonexistent-command").isEmpty)
  }

  func testEveryCatalogEntryHasAUniqueID() {
    let ids = CommandPaletteAction.all.map(\.id)
    XCTAssertEqual(ids.count, Set(ids).count)
  }
}
