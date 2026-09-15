//
//  StampIconTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class StampIconTests: XCTestCase {

  func testAllIcons_areIdentifiableByRawValue() {
    for icon in StampIcon.allCases {
      XCTAssertEqual(icon.id, icon.rawValue)
    }
  }

  func testAllIcons_haveDistinctSystemImageNames() {
    let names = StampIcon.allCases.map(\.systemImageName)
    XCTAssertEqual(Set(names).count, names.count, "Every stamp icon should map to a unique SF Symbol.")
  }

  func testAllIcons_haveDistinctDefaultColors() {
    let colors = StampIcon.allCases.map(\.defaultColor)
    XCTAssertEqual(Set(colors).count, colors.count, "Every stamp icon should have a visually distinct default color.")
  }

  func testCheck_mapsToCheckmarkSymbol() {
    XCTAssertEqual(StampIcon.check.systemImageName, "checkmark")
  }

  func testCross_mapsToXmarkSymbol() {
    XCTAssertEqual(StampIcon.cross.systemImageName, "xmark")
  }
}
