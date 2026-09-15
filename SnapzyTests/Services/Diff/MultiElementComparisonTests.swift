//
//  MultiElementComparisonTests.swift
//  SnapzyTests
//

import Foundation
import XCTest
@testable import Snapzy

final class MultiElementComparisonTests: XCTestCase {

  private func makeCardEvidence(id: String, borderRadius: String, fontSize: String = "14px") -> ElementEvidence {
    ElementEvidence(
      url: "https://example.com/collection", title: "Collection",
      viewport: .init(width: 1440, height: 900, devicePixelRatio: 2, scrollX: 0, scrollY: 0),
      locator: .init(candidates: [.init(strategy: .stableID, value: "#\(id)")]),
      rect: .init(x: 0, y: 0, width: 300, height: 400),
      typographyJSON: "{\"fontSize\":\"\(fontSize)\"}",
      appearanceJSON: "{\"borderRadius\":\"\(borderRadius)\"}"
    )
  }

  func testMultiElementComparisonMatchesTheWorkedExample() throws {
    // "Selected: 12 PLP cards / 11 use radius 8px / 1 uses radius 6px."
    var cards = (0..<11).map { makeCardEvidence(id: "card\($0)", borderRadius: "8px") }
    cards.append(makeCardEvidence(id: "card11", borderRadius: "6px"))

    let distributions = MultiElementComparison.compare(cards)
    let radiusDistribution = try XCTUnwrap(distributions.first { $0.category == "appearance" && $0.property == "borderRadius" })
    XCTAssertEqual(radiusDistribution.valueCounts.count, 2)
    XCTAssertEqual(radiusDistribution.valueCounts[0].value, "8px")
    XCTAssertEqual(radiusDistribution.valueCounts[0].count, 11)
    XCTAssertEqual(radiusDistribution.valueCounts[1].value, "6px")
    XCTAssertEqual(radiusDistribution.valueCounts[1].count, 1)
  }

  func testMultiElementComparisonReportsFullConsistencyAsOneValue() throws {
    let cards = (0..<5).map { makeCardEvidence(id: "card\($0)", borderRadius: "8px") }
    let distributions = MultiElementComparison.compare(cards)
    let radiusDistribution = try XCTUnwrap(distributions.first { $0.property == "borderRadius" })
    XCTAssertEqual(radiusDistribution.valueCounts.count, 1)
    XCTAssertEqual(radiusDistribution.valueCounts[0].count, 5)
  }

  func testMultiElementComparisonSortsLeastConsistentPropertiesFirst() throws {
    // fontSize is fully consistent (all 14px); borderRadius has an
    // outlier -- the outlier property should be reported first, since
    // it's the one actually worth a human's attention.
    var cards = (0..<3).map { makeCardEvidence(id: "card\($0)", borderRadius: "8px", fontSize: "14px") }
    cards.append(makeCardEvidence(id: "card3", borderRadius: "6px", fontSize: "14px"))

    let distributions = MultiElementComparison.compare(cards)
    let radiusIndex = try XCTUnwrap(distributions.firstIndex { $0.property == "borderRadius" })
    let fontSizeIndex = try XCTUnwrap(distributions.firstIndex { $0.property == "fontSize" })
    XCTAssertLessThan(radiusIndex, fontSizeIndex)
  }

  func testMultiElementComparisonIncludesRectDimensions() throws {
    var evidenceA = makeCardEvidence(id: "a", borderRadius: "8px")
    evidenceA.rect = Region(x: 0, y: 0, width: 300, height: 400)
    var evidenceB = makeCardEvidence(id: "b", borderRadius: "8px")
    evidenceB.rect = Region(x: 0, y: 0, width: 320, height: 400)

    let distributions = MultiElementComparison.compare([evidenceA, evidenceB])
    let widthDistribution = try XCTUnwrap(distributions.first { $0.category == "rect" && $0.property == "width" })
    XCTAssertEqual(widthDistribution.valueCounts.count, 2)
    let heightDistribution = try XCTUnwrap(distributions.first { $0.category == "rect" && $0.property == "height" })
    XCTAssertEqual(heightDistribution.valueCounts.count, 1)
  }

  func testMultiElementComparisonWithFewerThanTwoEvidencesIsEmpty() {
    XCTAssertTrue(MultiElementComparison.compare([makeCardEvidence(id: "solo", borderRadius: "8px")]).isEmpty)
    XCTAssertTrue(MultiElementComparison.compare([]).isEmpty)
  }
}
