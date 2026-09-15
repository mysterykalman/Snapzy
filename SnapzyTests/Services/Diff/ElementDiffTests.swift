//
//  ElementDiffTests.swift
//  SnapzyTests
//

import Foundation
import XCTest
@testable import Snapzy

final class ElementDiffTests: XCTestCase {

  private func makeEvidence(
    stableID: String,
    rect: Region = .init(x: 0, y: 0, width: 100, height: 50),
    typographyJSON: String? = nil,
    appearanceJSON: String? = nil,
    boxModelJSON: String? = nil
  ) -> ElementEvidence {
    ElementEvidence(
      url: "https://example.com", title: "Example",
      viewport: .init(width: 1440, height: 900, devicePixelRatio: 2, scrollX: 0, scrollY: 0),
      locator: .init(candidates: [.init(strategy: .stableID, value: stableID)]),
      rect: rect,
      typographyJSON: typographyJSON,
      appearanceJSON: appearanceJSON,
      boxModelJSON: boxModelJSON
    )
  }

  func testIsLikelySameElementTrueWhenLocatorsShareACandidate() {
    let before = makeEvidence(stableID: "#a")
    let after = makeEvidence(stableID: "#a")
    XCTAssertTrue(ElementDiff.isLikelySameElement(before, after))
  }

  func testIsLikelySameElementFalseWhenLocatorsShareNoCandidate() {
    let before = makeEvidence(stableID: "#a")
    let after = makeEvidence(stableID: "#b")
    XCTAssertFalse(ElementDiff.isLikelySameElement(before, after))
  }

  func testDiffReportsRectPropertyChangesOnly() {
    let before = makeEvidence(stableID: "#a", rect: .init(x: 0, y: 0, width: 100, height: 50))
    let after = makeEvidence(stableID: "#a", rect: .init(x: 0, y: 0, width: 150, height: 50))
    let differences = ElementDiff.diff(before, after)
    XCTAssertEqual(differences, [PropertyDifference(category: "rect", property: "width", before: "100", after: "150")])
  }

  func testDiffReportsChangedTypographyKeys() {
    let before = makeEvidence(stableID: "#a", typographyJSON: "{\"fontSize\":14}")
    let after = makeEvidence(stableID: "#a", typographyJSON: "{\"fontSize\":16}")
    let differences = ElementDiff.diff(before, after)
    XCTAssertTrue(differences.contains(PropertyDifference(category: "typography", property: "fontSize", before: "14", after: "16")))
  }

  func testDiffReportsAKeyPresentOnlyOnOneSide() {
    let before = makeEvidence(stableID: "#a", appearanceJSON: "{\"--brand-color\":\"blue\"}")
    let after = makeEvidence(stableID: "#a", appearanceJSON: "{}")
    let differences = ElementDiff.diff(before, after)
    XCTAssertTrue(differences.contains(PropertyDifference(category: "appearance", property: "--brand-color", before: "blue", after: "")))
  }

  func testDiffReportsNoDifferencesForIdenticalEvidence() {
    let before = makeEvidence(stableID: "#a", boxModelJSON: "{\"padding\":8}")
    let after = makeEvidence(stableID: "#a", boxModelJSON: "{\"padding\":8}")
    XCTAssertTrue(ElementDiff.diff(before, after).isEmpty)
  }
}
