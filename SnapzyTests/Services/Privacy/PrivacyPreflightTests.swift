//
//  PrivacyPreflightTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class PrivacyPreflightTests: XCTestCase {

  func testDetectsEmail() {
    let matches = PrivacyPreflight.scan("Contact me at jane.doe@example.com for details.")
    XCTAssertTrue(matches.contains { $0.category == .email && $0.text == "jane.doe@example.com" })
  }

  func testDetectsPhoneNumber() {
    let matches = PrivacyPreflight.scan("Call (415) 555-0132 for support.")
    XCTAssertTrue(matches.contains { $0.category == .phone })
  }

  func testDetectsValidCreditCardButRejectsInvalidLuhn() {
    // A real, Luhn-valid test number (Visa test card format).
    let valid = PrivacyPreflight.scan("Card: 4111 1111 1111 1111")
    XCTAssertTrue(valid.contains { $0.category == .creditCard })

    // A random 16-digit run that fails the Luhn check must not match.
    let invalid = PrivacyPreflight.scan("Order number: 1234 5678 9012 3459")
    XCTAssertFalse(invalid.contains { $0.category == .creditCard })
  }

  func testDetectsAPIKeyShapedToken() {
    // A long opaque token, deliberately not shaped like any real
    // provider's key format (no sk_/pk_/ghp_/etc. prefix, which the
    // pattern doesn't require anyway) so this can't be mistaken for a
    // real leaked credential by a secret scanner.
    let matches = PrivacyPreflight.scan("token: qzxmvbnlkjhgfdsapoiuytrewq0123456789")
    XCTAssertTrue(matches.contains { $0.category == .apiKey })
  }

  func testDetectsIPAddress() {
    let matches = PrivacyPreflight.scan("Server responded from 192.168.1.42.")
    XCTAssertTrue(matches.contains { $0.category == .ipAddress && $0.text == "192.168.1.42" })
  }

  func testDetectsConfidentialTermsCaseInsensitively() {
    let matches = PrivacyPreflight.scan("Project OPERATION FIREBIRD is confidential.", confidentialTerms: ["operation firebird"])
    XCTAssertTrue(matches.contains { $0.category == .confidentialTerm })
  }

  func testCountsGroupsByCategory() {
    let matches = PrivacyPreflight.scan("a@b.com and c@d.com plus 192.168.1.1")
    let counts = PrivacyPreflight.counts(matches)
    XCTAssertEqual(counts[.email], 2)
    XCTAssertEqual(counts[.ipAddress], 1)
  }

  func testCleanTextProducesNoMatches() {
    XCTAssertTrue(PrivacyPreflight.scan("Just a plain screenshot with no sensitive text at all.").isEmpty)
  }
}
