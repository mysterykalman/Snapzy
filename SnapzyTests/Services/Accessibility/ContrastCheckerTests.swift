//
//  ContrastCheckerTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class ContrastCheckerTests: XCTestCase {

  private let black = ContrastChecker.RGB(red: 0, green: 0, blue: 0)
  private let white = ContrastChecker.RGB(red: 1, green: 1, blue: 1)

  func testBlackOnWhiteRatioIsTwentyOneToOne() {
    XCTAssertEqual(ContrastChecker.wcagContrastRatio(black, white), 21, accuracy: 0.01)
  }

  func testSameColorRatioIsOneToOne() {
    let gray = ContrastChecker.RGB(red: 0.5, green: 0.5, blue: 0.5)
    XCTAssertEqual(ContrastChecker.wcagContrastRatio(gray, gray), 1, accuracy: 0.001)
  }

  func testRatioIsOrderIndependent() {
    let ratioA = ContrastChecker.wcagContrastRatio(black, white)
    let ratioB = ContrastChecker.wcagContrastRatio(white, black)
    XCTAssertEqual(ratioA, ratioB, accuracy: 0.0001)
  }

  func testWCAGLevelThresholdsForNormalText() {
    XCTAssertEqual(ContrastChecker.wcagLevel(ratio: 21, isLargeText: false), .aaa)
    XCTAssertEqual(ContrastChecker.wcagLevel(ratio: 5, isLargeText: false), .aa)
    XCTAssertEqual(ContrastChecker.wcagLevel(ratio: 2, isLargeText: false), .fail)
  }

  func testWCAGLevelThresholdsForLargeText() {
    XCTAssertEqual(ContrastChecker.wcagLevel(ratio: 4.5, isLargeText: true), .aaa)
    XCTAssertEqual(ContrastChecker.wcagLevel(ratio: 3.5, isLargeText: true), .aa)
    XCTAssertEqual(ContrastChecker.wcagLevel(ratio: 2, isLargeText: true), .fail)
  }

  func testSuggestCompliantForegroundReturnsOriginalWhenAlreadyCompliant() {
    let suggestion = ContrastChecker.suggestCompliantForeground(foreground: black, background: white, targetRatio: 4.5)
    XCTAssertEqual(suggestion, black)
  }

  func testSuggestCompliantForegroundMeetsTargetRatio() {
    // A low-contrast light gray on white background is not compliant.
    let lightGray = ContrastChecker.RGB(red: 0.85, green: 0.85, blue: 0.85)
    let suggestion = ContrastChecker.suggestCompliantForeground(foreground: lightGray, background: white, targetRatio: 4.5)
    XCTAssertGreaterThanOrEqual(ContrastChecker.wcagContrastRatio(suggestion, white), 4.5 - 0.01)
  }

  func testSuggestCompliantForegroundFallsBackToBestExtremeWhenUnreachable() {
    // Mid-gray on mid-gray background can never reach a 21:1 target —
    // must fall back to whichever extreme (black/white) does best.
    let gray = ContrastChecker.RGB(red: 0.5, green: 0.5, blue: 0.5)
    let suggestion = ContrastChecker.suggestCompliantForeground(foreground: gray, background: gray, targetRatio: 21)
    XCTAssertTrue(suggestion == black || suggestion == white)
  }
}
