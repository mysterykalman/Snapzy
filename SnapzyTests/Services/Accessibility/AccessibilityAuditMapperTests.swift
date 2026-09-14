//
//  AccessibilityAuditMapperTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class AccessibilityAuditMapperTests: XCTestCase {

  private let fullJSON = """
    {
      "headingOutline": {
        "headings": [{ "level": 2, "text": "Welcome", "tagName": "H2" }],
        "issues": [{ "type": "missingH1", "message": "Page has no H1 heading." }]
      },
      "images": [
        { "src": "/hero.jpg", "isPresentation": false, "hasAlt": false, "isInsideLink": false, "missingAlt": true },
        { "src": "/logo.png", "isPresentation": false, "hasAlt": true, "isInsideLink": false, "missingAlt": false }
      ],
      "links": [
        { "href": "/pricing", "accessibleName": "Click here", "isEmpty": false, "isVague": true },
        { "href": "/about", "accessibleName": "About us", "isEmpty": false, "isVague": false }
      ],
      "forms": [
        { "tagName": "INPUT", "type": "email", "isLabeled": false, "isRequired": true }
      ],
      "duplicateIds": [{ "id": "header", "count": 2 }],
      "htmlLang": { "lang": null, "isMissing": true },
      "positiveTabIndexElements": [{ "tagName": "DIV", "tabIndex": 5 }]
    }
    """

  func testMapsOneFindingPerRealIssueAcrossAllCategories() throws {
    let findings = try AccessibilityAuditMapper.mapFindings(fromAuditJSON: fullJSON, page: "https://example.com", viewportWidth: 1440, viewportHeight: 900)

    XCTAssertTrue(findings.contains { $0.title == "Missing H1 heading" })
    XCTAssertTrue(findings.contains { $0.finding.contains("/hero.jpg") })
    XCTAssertFalse(findings.contains { $0.finding.contains("/logo.png") }) // has alt text, no finding
    XCTAssertTrue(findings.contains { $0.title == "Vague link text" })
    XCTAssertFalse(findings.contains { $0.finding.contains("/about") }) // not vague, no finding
    XCTAssertTrue(findings.contains { $0.title == "Form field missing a label" })
    XCTAssertTrue(findings.contains { $0.title == "Duplicate id attribute" })
    XCTAssertTrue(findings.contains { $0.title.contains("html lang") })
    XCTAssertTrue(findings.contains { $0.title.contains("tabindex") })
  }

  func testEveryMappedFindingCarriesThePageAndViewport() throws {
    let findings = try AccessibilityAuditMapper.mapFindings(fromAuditJSON: fullJSON, page: "https://example.com/pdp", viewportWidth: 375, viewportHeight: 812)
    XCTAssertFalse(findings.isEmpty)
    for finding in findings {
      XCTAssertEqual(finding.page, "https://example.com/pdp")
      XCTAssertEqual(finding.viewportWidth, 375)
      XCTAssertEqual(finding.viewportHeight, 812)
      XCTAssertEqual(finding.category, "Accessibility")
    }
  }

  func testOlderJSONShapeWithoutOptionalFieldsStillDecodes() throws {
    let minimalJSON = """
      {
        "headingOutline": { "headings": [], "issues": [] },
        "images": [],
        "links": [],
        "forms": []
      }
      """
    let findings = try AccessibilityAuditMapper.mapFindings(fromAuditJSON: minimalJSON, page: "https://example.com", viewportWidth: nil, viewportHeight: nil)
    XCTAssertTrue(findings.isEmpty)
  }

  func testCleanPageProducesNoFindings() throws {
    let cleanJSON = """
      {
        "headingOutline": { "headings": [{ "level": 1, "text": "Home", "tagName": "H1" }], "issues": [] },
        "images": [{ "src": "/a.png", "isPresentation": false, "hasAlt": true, "isInsideLink": false, "missingAlt": false }],
        "links": [{ "href": "/x", "accessibleName": "Visit our store", "isEmpty": false, "isVague": false }],
        "forms": [{ "tagName": "INPUT", "type": "text", "isLabeled": true, "isRequired": false }],
        "duplicateIds": [],
        "htmlLang": { "lang": "en", "isMissing": false },
        "positiveTabIndexElements": []
      }
      """
    let findings = try AccessibilityAuditMapper.mapFindings(fromAuditJSON: cleanJSON, page: "https://example.com", viewportWidth: nil, viewportHeight: nil)
    XCTAssertTrue(findings.isEmpty)
  }

  func testInvalidJSONThrows() {
    XCTAssertThrowsError(try AccessibilityAuditMapper.mapFindings(fromAuditJSON: "not json", page: "https://example.com", viewportWidth: nil, viewportHeight: nil))
  }

  func testMissingRequiredTopLevelKeyThrows() {
    let missingImages = """
      { "headingOutline": { "headings": [], "issues": [] }, "links": [], "forms": [] }
      """
    XCTAssertThrowsError(try AccessibilityAuditMapper.mapFindings(fromAuditJSON: missingImages, page: "https://example.com", viewportWidth: nil, viewportHeight: nil))
  }
}
