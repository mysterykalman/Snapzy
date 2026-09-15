//
//  EcommerceAuditMapperTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class EcommerceAuditMapperTests: XCTestCase {

  func testPriceMismatchProducesAHighSeverityPDPFinding() throws {
    let json = """
      {
        "priceConsistencyCheck": { "schemaPrice": 29.99, "visiblePrice": 24.99, "matches": false }
      }
      """
    let result = try EcommerceAuditMapper.map(fromSnapshotJSON: json, page: "https://example.com/products/widget", viewportWidth: 1440, viewportHeight: 900)

    XCTAssertEqual(result.findings.count, 1)
    let finding = try XCTUnwrap(result.findings.first)
    XCTAssertEqual(finding.category, "PDP")
    XCTAssertEqual(finding.severity, AuditFinding.DefaultSeverity.high)
    XCTAssertTrue(finding.finding.contains("29.99"))
    XCTAssertTrue(finding.finding.contains("24.99"))
  }

  func testMatchingPriceProducesNoFinding() throws {
    let json = """
      { "priceConsistencyCheck": { "schemaPrice": 29.99, "visiblePrice": 29.99, "matches": true } }
      """
    let result = try EcommerceAuditMapper.map(fromSnapshotJSON: json, page: "https://example.com", viewportWidth: nil, viewportHeight: nil)
    XCTAssertTrue(result.findings.isEmpty)
  }

  func testNullMatchesProducesNoFindingRatherThanAFalsePositive() throws {
    // matches: null means "not enough data to compare" -- not a mismatch.
    let json = """
      { "priceConsistencyCheck": { "schemaPrice": null, "visiblePrice": 15.5, "matches": null } }
      """
    let result = try EcommerceAuditMapper.map(fromSnapshotJSON: json, page: "https://example.com", viewportWidth: nil, viewportHeight: nil)
    XCTAssertTrue(result.findings.isEmpty)
  }

  func testCartPriceMismatchProducesAHighSeverityCartFinding() throws {
    let json = """
      {
        "cartPriceConsistencyCheck": { "matches": false, "expectedCartPrice": 49.99, "pdpPrice": 59.99, "cartPrice": 55.00, "discountAmount": 10 }
      }
      """
    let result = try EcommerceAuditMapper.map(fromSnapshotJSON: json, page: "https://example.com/cart", viewportWidth: nil, viewportHeight: nil)

    XCTAssertEqual(result.findings.count, 1)
    let finding = try XCTUnwrap(result.findings.first)
    XCTAssertEqual(finding.category, "Cart")
    XCTAssertTrue(finding.finding.contains("49.99"))
    XCTAssertTrue(finding.finding.contains("55.00"))
  }

  func testBothMismatchesProduceTwoFindings() throws {
    let json = """
      {
        "priceConsistencyCheck": { "schemaPrice": 29.99, "visiblePrice": 24.99, "matches": false },
        "cartPriceConsistencyCheck": { "matches": false, "expectedCartPrice": 49.99, "pdpPrice": 59.99, "cartPrice": 55.00, "discountAmount": 10 }
      }
      """
    let result = try EcommerceAuditMapper.map(fromSnapshotJSON: json, page: "https://example.com", viewportWidth: nil, viewportHeight: nil)
    XCTAssertEqual(result.findings.count, 2)
    XCTAssertTrue(result.findings.contains { $0.category == "PDP" })
    XCTAssertTrue(result.findings.contains { $0.category == "Cart" })
  }

  func testTechnologyAndComponentDetectionsPassThroughWithoutBecomingFindings() throws {
    let json = """
      {
        "technologyFingerprint": [
          { "technology": "Shopify", "category": "platform", "confidence": "high", "signals": ["window.Shopify global present", "script from cdn.shopify.com"] }
        ],
        "croComponentClassification": [
          { "component": "stickyAddToCart", "confidence": "medium", "signals": ["authored position:sticky combined with an Add to Cart identifier"], "selector": "#sticky-atc" }
        ]
      }
      """
    let result = try EcommerceAuditMapper.map(fromSnapshotJSON: json, page: "https://example.com", viewportWidth: nil, viewportHeight: nil)

    XCTAssertTrue(result.findings.isEmpty, "detections alone are not findings")
    XCTAssertEqual(result.technologyDetections.count, 1)
    XCTAssertEqual(result.technologyDetections.first?.technology, "Shopify")
    XCTAssertEqual(result.componentDetections.count, 1)
    XCTAssertEqual(result.componentDetections.first?.component, "stickyAddToCart")
  }

  func testEmptySnapshotProducesNoFindingsAndNoDetections() throws {
    let result = try EcommerceAuditMapper.map(fromSnapshotJSON: "{}", page: "https://example.com", viewportWidth: nil, viewportHeight: nil)
    XCTAssertTrue(result.findings.isEmpty)
    XCTAssertTrue(result.technologyDetections.isEmpty)
    XCTAssertTrue(result.componentDetections.isEmpty)
    XCTAssertNil(result.shopifyTheme)
  }

  func testShopifyThemeIntelligencePassesThroughWithoutBecomingAFinding() throws {
    let json = """
      {
        "shopifyThemeIntelligence": {
          "themeName": "Dawn", "themeId": 123, "themeStoreId": 796,
          "templateType": "product", "sectionIds": ["header", "main-product"], "appBlockIds": ["block-1"]
        }
      }
      """
    let result = try EcommerceAuditMapper.map(fromSnapshotJSON: json, page: "https://example.com", viewportWidth: nil, viewportHeight: nil)

    XCTAssertTrue(result.findings.isEmpty, "theme intelligence alone is not a finding")
    let theme = try XCTUnwrap(result.shopifyTheme)
    XCTAssertEqual(theme.themeName, "Dawn")
    XCTAssertEqual(theme.themeId, 123)
    XCTAssertEqual(theme.templateType, "product")
    XCTAssertEqual(theme.sectionIds, ["header", "main-product"])
  }

  func testInvalidJSONThrows() {
    XCTAssertThrowsError(try EcommerceAuditMapper.map(fromSnapshotJSON: "not json", page: "https://example.com", viewportWidth: nil, viewportHeight: nil))
  }
}
