//
//  ElementLocatorTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class ElementLocatorTests: XCTestCase {

  func testPrimaryPrefersStrongestAvailableStrategy() {
    let locator = ElementLocator(candidates: [
      .init(strategy: .absoluteDOMPath, value: "/html/body/div[2]"),
      .init(strategy: .dataTestID, value: "checkout-button"),
      .init(strategy: .classAndStructure, value: ".btn.primary"),
    ])
    XCTAssertEqual(locator.primary?.strategy, .dataTestID)
    XCTAssertEqual(locator.primary?.value, "checkout-button")
  }

  func testPrimaryFallsBackWhenStrongestStrategiesAreAbsent() {
    let locator = ElementLocator(candidates: [
      .init(strategy: .absoluteDOMPath, value: "/html/body/div[2]"),
      .init(strategy: .textFingerprint, value: "Add to cart"),
    ])
    XCTAssertEqual(locator.primary?.strategy, .textFingerprint)
  }

  func testPrimaryIsNilWithNoCandidates() {
    XCTAssertNil(ElementLocator(candidates: []).primary)
  }

  func testRoundTripsThroughJSON() throws {
    let locator = ElementLocator(candidates: [.init(strategy: .stableID, value: "#main-nav")])
    let data = try JSONEncoder().encode(locator)
    let decoded = try JSONDecoder().decode(ElementLocator.self, from: data)
    XCTAssertEqual(decoded, locator)
  }
}
