//
//  ContentDiffTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class ContentDiffTests: XCTestCase {

  func testIdenticalTextProducesNoChanges() {
    let before = ["#title": "Welcome", "#price": "$19.99"]
    let after = ["#title": "Welcome", "#price": "$19.99"]
    XCTAssertTrue(ContentDiff.diff(before: before, after: after).isEmpty)
  }

  func testChangedTextIsReportedWithBeforeAndAfter() {
    let before = ["#price": "$19.99"]
    let after = ["#price": "$24.99"]
    let changes = ContentDiff.diff(before: before, after: after)
    XCTAssertEqual(changes, [ContentChange(selector: "#price", kind: .changed, before: "$19.99", after: "$24.99")])
  }

  func testASelectorPresentOnlyInAfterIsReportedAsAdded() {
    let before: [String: String] = [:]
    let after = ["#banner": "New sale!"]
    let changes = ContentDiff.diff(before: before, after: after)
    XCTAssertEqual(changes, [ContentChange(selector: "#banner", kind: .added, before: nil, after: "New sale!")])
  }

  func testASelectorPresentOnlyInBeforeIsReportedAsRemoved() {
    let before = ["#banner": "Old sale!"]
    let after: [String: String] = [:]
    let changes = ContentDiff.diff(before: before, after: after)
    XCTAssertEqual(changes, [ContentChange(selector: "#banner", kind: .removed, before: "Old sale!", after: nil)])
  }

  func testResultsAreSortedBySelectorRegardlessOfDictionaryOrder() {
    let before = ["#z": "1", "#a": "2", "#m": "3"]
    let after = ["#z": "1x", "#a": "2x", "#m": "3x"]
    let changes = ContentDiff.diff(before: before, after: after)
    XCTAssertEqual(changes.map(\.selector), ["#a", "#m", "#z"])
  }

  func testAMixOfAddedRemovedAndChangedAllReportCorrectly() {
    let before = ["#stays-same": "hello", "#removed": "gone soon", "#changes": "old text"]
    let after = ["#stays-same": "hello", "#added": "brand new", "#changes": "new text"]
    let changes = ContentDiff.diff(before: before, after: after)
    XCTAssertEqual(changes.count, 3)
    XCTAssertTrue(changes.contains(ContentChange(selector: "#added", kind: .added, before: nil, after: "brand new")))
    XCTAssertTrue(changes.contains(ContentChange(selector: "#removed", kind: .removed, before: "gone soon", after: nil)))
    XCTAssertTrue(changes.contains(ContentChange(selector: "#changes", kind: .changed, before: "old text", after: "new text")))
  }

  func testEmptySnapshotsProduceNoChanges() {
    XCTAssertTrue(ContentDiff.diff(before: [:], after: [:]).isEmpty)
  }
}
