//
//  SmartRedactTests.swift
//  SnapzyTests
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class SmartRedactTests: XCTestCase {

  func testProposesRedactionForEachMatchWithItsLineBoundingBox() {
    let observations: [(text: String, boundingBox: CGRect)] = [
      (text: "Email me at jane@example.com", boundingBox: CGRect(x: 0, y: 0.8, width: 1, height: 0.1)),
      (text: "Totally harmless line", boundingBox: CGRect(x: 0, y: 0.6, width: 1, height: 0.1)),
    ]

    let proposals = SmartRedact.proposeRedactions(observations: observations)
    XCTAssertEqual(proposals.count, 1)
    XCTAssertEqual(proposals[0].category, .email)
    XCTAssertEqual(proposals[0].region, CGRect(x: 0, y: 0.8, width: 1, height: 0.1))
  }

  func testMatchSpanningTwoLinesIsNotDetected() {
    // Documented limitation: a pattern split across two OCR lines is
    // invisible to per-line scanning.
    let observations: [(text: String, boundingBox: CGRect)] = [
      (text: "jane.doe@exam", boundingBox: CGRect(x: 0, y: 0.8, width: 0.5, height: 0.1)),
      (text: "ple.com", boundingBox: CGRect(x: 0, y: 0.7, width: 0.5, height: 0.1)),
    ]
    XCTAssertTrue(SmartRedact.proposeRedactions(observations: observations).isEmpty)
  }

  func testConfidentialTermsArePassedThrough() {
    let observations: [(text: String, boundingBox: CGRect)] = [
      (text: "Project Nightingale status update", boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1))
    ]
    let proposals = SmartRedact.proposeRedactions(observations: observations, confidentialTerms: ["Project Nightingale"])
    XCTAssertEqual(proposals.count, 1)
    XCTAssertEqual(proposals[0].category, .confidentialTerm)
  }

  func testNoObservationsProducesNoProposals() {
    XCTAssertTrue(SmartRedact.proposeRedactions(observations: []).isEmpty)
  }
}
