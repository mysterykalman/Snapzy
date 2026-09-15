//
//  PageLayoutDiffTests.swift
//  SnapzyTests
//

import Foundation
import XCTest
@testable import Snapzy

final class PageLayoutDiffTests: XCTestCase {

  private func makeEvidence(id: String, rect: Region, text: String = "unused") -> ElementEvidence {
    ElementEvidence(
      url: "https://example.com", title: "Example",
      viewport: .init(width: 1440, height: 900, devicePixelRatio: 2, scrollX: 0, scrollY: 0),
      locator: .init(candidates: [.init(strategy: .stableID, value: "#\(id)")]),
      rect: rect
    )
  }

  func testPageLayoutDiffReportsUnchangedForIdenticalRects() {
    let before = [makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 100, height: 50))]
    let after = [makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 100, height: 50))]
    let changes = PageLayoutDiff.diff(before: before, after: after)
    XCTAssertEqual(changes.count, 1)
    XCTAssertEqual(changes[0].kind, .unchanged)
  }

  func testPageLayoutDiffIgnoresRoundingNoiseWithinTolerance() {
    let before = [makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 100, height: 50))]
    let after = [makeEvidence(id: "a", rect: .init(x: 0.2, y: -0.1, width: 100, height: 50))]
    let changes = PageLayoutDiff.diff(before: before, after: after, tolerance: 0.5)
    XCTAssertEqual(changes[0].kind, .unchanged)
  }

  func testPageLayoutDiffDetectsAPureMove() {
    let before = [makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 100, height: 50))]
    let after = [makeEvidence(id: "a", rect: .init(x: 20, y: 10, width: 100, height: 50))]
    let changes = PageLayoutDiff.diff(before: before, after: after)
    XCTAssertEqual(changes[0].kind, .moved(dx: 20, dy: 10))
  }

  func testPageLayoutDiffDetectsAPureResize() {
    let before = [makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 100, height: 50))]
    let after = [makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 150, height: 60))]
    let changes = PageLayoutDiff.diff(before: before, after: after)
    XCTAssertEqual(changes[0].kind, .resized(dWidth: 50, dHeight: 10))
  }

  func testPageLayoutDiffDetectsMoveAndResizeTogether() {
    let before = [makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 100, height: 50))]
    let after = [makeEvidence(id: "a", rect: .init(x: 20, y: 0, width: 150, height: 50))]
    let changes = PageLayoutDiff.diff(before: before, after: after)
    XCTAssertEqual(changes[0].kind, .movedAndResized(dx: 20, dy: 0, dWidth: 50, dHeight: 0))
  }

  func testPageLayoutDiffReportsAddedAndRemovedElements() {
    let before = [makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 10, height: 10))]
    let after = [makeEvidence(id: "b", rect: .init(x: 0, y: 0, width: 10, height: 10))]
    let changes = PageLayoutDiff.diff(before: before, after: after)
    XCTAssertEqual(changes.count, 2)
    XCTAssertTrue(changes.contains { $0.kind == .removed && $0.before?.locator.primary?.value == "#a" })
    XCTAssertTrue(changes.contains { $0.kind == .added && $0.after?.locator.primary?.value == "#b" })
  }

  func testPageLayoutDiffIgnoresContentChangesEntirely() {
    // Same element, same geometry, but the underlying content (modeled
    // here via typographyJSON, since ElementEvidence has no bare "text"
    // field) differs -- layout diff must report unchanged, since content
    // is explicitly out of scope for this mode.
    var before = makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 100, height: 20))
    before.typographyJSON = "{\"text\":\"$19.99\"}"
    var after = makeEvidence(id: "a", rect: .init(x: 0, y: 0, width: 100, height: 20))
    after.typographyJSON = "{\"text\":\"$24.99\"}"

    let changes = PageLayoutDiff.diff(before: [before], after: [after])
    XCTAssertEqual(changes[0].kind, .unchanged)
  }
}
