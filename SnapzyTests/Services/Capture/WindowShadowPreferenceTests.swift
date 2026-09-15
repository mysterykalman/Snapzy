//
//  WindowShadowPreferenceTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class WindowShadowPreferenceTests: XCTestCase {
  func testIgnoreShadowsSingleWindow_invertsIncludeShadowFlag() {
    // shadow included  -> SC must NOT ignore shadows
    XCTAssertEqual(WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: true), false)
    // shadow excluded  -> SC must ignore shadows
    XCTAssertEqual(WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: false), true)
  }

  func testDefaultIncludeShadow_preservesLegacyShadowOnBehavior() {
    // Default must keep shadow ON so existing users see no behavior change.
    XCTAssertEqual(WindowShadowPreference.defaultIncludeShadow, true)
  }

  // `resolvedIncludeShadow` reads the live, real `NSEvent.modifierFlags`
  // (Option-click captures a window without its shadow) with no
  // injectable seam -- there's no way to simulate "Option is held" in a
  // headless CI runner. This only exercises the deterministic branch
  // (Option genuinely not held while the test runs, which is always
  // true in CI): the stored preference passes through unchanged.
  func testResolvedIncludeShadow_passesThroughStoredPreferenceWhenOptionIsNotHeld() {
    XCTAssertEqual(WindowShadowPreference.resolvedIncludeShadow(storedIncludeShadow: true), true)
    XCTAssertEqual(WindowShadowPreference.resolvedIncludeShadow(storedIncludeShadow: false), false)
  }
}
