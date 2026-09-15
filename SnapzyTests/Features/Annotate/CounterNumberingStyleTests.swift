//
//  CounterNumberingStyleTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class CounterNumberingStyleTests: XCTestCase {

  func testNumericLabel_returnsPlainDecimalValue() {
    XCTAssertEqual(CounterNumberingStyle.numeric.label(for: 1), "1")
    XCTAssertEqual(CounterNumberingStyle.numeric.label(for: 42), "42")
  }

  func testAlphabeticLabel_mapsSingleLetterRange() {
    XCTAssertEqual(CounterNumberingStyle.alphabetic.label(for: 1), "A")
    XCTAssertEqual(CounterNumberingStyle.alphabetic.label(for: 2), "B")
    XCTAssertEqual(CounterNumberingStyle.alphabetic.label(for: 26), "Z")
  }

  func testAlphabeticLabel_overflowsToDoubleLettersSpreadsheetStyle() {
    XCTAssertEqual(CounterNumberingStyle.alphabetic.label(for: 27), "AA")
    XCTAssertEqual(CounterNumberingStyle.alphabetic.label(for: 28), "AB")
    XCTAssertEqual(CounterNumberingStyle.alphabetic.label(for: 52), "AZ")
    XCTAssertEqual(CounterNumberingStyle.alphabetic.label(for: 53), "BA")
  }

  func testRomanLabel_mapsKnownValues() {
    XCTAssertEqual(CounterNumberingStyle.roman.label(for: 1), "I")
    XCTAssertEqual(CounterNumberingStyle.roman.label(for: 4), "IV")
    XCTAssertEqual(CounterNumberingStyle.roman.label(for: 9), "IX")
    XCTAssertEqual(CounterNumberingStyle.roman.label(for: 14), "XIV")
    XCTAssertEqual(CounterNumberingStyle.roman.label(for: 40), "XL")
    XCTAssertEqual(CounterNumberingStyle.roman.label(for: 99), "XCIX")
    XCTAssertEqual(CounterNumberingStyle.roman.label(for: 2024), "MMXXIV")
  }

  func testAllStyles_areIdentifiableByRawValue() {
    for style in CounterNumberingStyle.allCases {
      XCTAssertEqual(style.id, style.rawValue)
    }
  }
}
