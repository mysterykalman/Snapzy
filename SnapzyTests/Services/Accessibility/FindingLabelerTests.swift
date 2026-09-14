//
//  FindingLabelerTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class FindingLabelerTests: XCTestCase {

  func testKnownCategoryUsesItsFixedAbbreviation() {
    XCTAssertEqual(FindingLabeler.abbreviation(for: "Navigation"), "NAV")
    XCTAssertEqual(FindingLabeler.abbreviation(for: "PDP"), "PDP")
    XCTAssertEqual(FindingLabeler.abbreviation(for: "Accessibility"), "A11Y")
  }

  func testUnknownCategoryFallsBackToFirstFourLetters() {
    XCTAssertEqual(FindingLabeler.abbreviation(for: "Onboarding"), "ONBO")
  }

  func testUnknownCategoryWithNoLettersFallsBackToMisc() {
    XCTAssertEqual(FindingLabeler.abbreviation(for: "123"), "MISC")
  }

  func testFirstLabelForACategoryIsNumberOne() {
    XCTAssertEqual(FindingLabeler.nextLabel(for: "Navigation", existingLabels: []), "NAV-01")
  }

  func testNextLabelContinuesSequenceRegardlessOfInputOrder() {
    let existing = ["NAV-03", "NAV-01", "NAV-02"]
    XCTAssertEqual(FindingLabeler.nextLabel(for: "Navigation", existingLabels: existing), "NAV-04")
  }

  func testNextLabelIgnoresLabelsFromOtherCategories() {
    let existing = ["PDP-01", "PDP-02"]
    XCTAssertEqual(FindingLabeler.nextLabel(for: "Navigation", existingLabels: existing), "NAV-01")
  }

  func testLabelsAreZeroPaddedToTwoDigits() {
    XCTAssertEqual(FindingLabeler.nextLabel(for: "PDP", existingLabels: []), "PDP-01")
  }

  func testLabelNumberingContinuesPastNinetyNineWithoutPadding() {
    let existing = ["PDP-99"]
    XCTAssertEqual(FindingLabeler.nextLabel(for: "PDP", existingLabels: existing), "PDP-100")
  }
}
