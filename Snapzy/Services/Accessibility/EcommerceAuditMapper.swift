//
//  EcommerceAuditMapper.swift
//  Snapzy
//
//  Converts a subset of the raw JSON extensions/chromium/src/
//  ecommerce-intelligence.js produces into real AuditFindings (the same
//  shared record shape AccessibilityAuditMapper uses) plus typed,
//  non-finding evidence models for informational display.
//
//  Unlike accessibility-audit.js's single runAccessibilityAudit() that
//  bundles a whole-page pass with no caller input, several of
//  ecommerce-intelligence.js's functions need a caller-supplied CSS
//  selector (plpCardScan, ecommerceImageAudit, recommendationsIntelligence)
//  and so can't be folded into one generic page-wide snapshot. This
//  mapper covers the selector-free subset a content script can always
//  gather on its own: technology fingerprinting, PDP-vs-visible price
//  consistency, and CRO component classification.
//
//  Technology detection and CRO component classification are
//  deliberately NOT mapped to AuditFinding: detecting that a page uses
//  Shopify or has a sticky Add to Cart button is not itself a problem to
//  review/resolve, and turning every detection into a "finding" would
//  bury the real, actionable ones (a genuine price mismatch) in noise.
//  They're exposed as their own typed, decodable evidence models instead
//  for a future informational display.
//

import Foundation

enum EcommerceAuditMapper {
  struct RawPriceConsistency: Decodable {
    var schemaPrice: Double?
    var visiblePrice: Double?
    var matches: Bool?
  }

  struct RawCartPriceConsistency: Decodable {
    var matches: Bool?
    var expectedCartPrice: Double?
    var pdpPrice: Double?
    var cartPrice: Double?
    var discountAmount: Double?
  }

  struct RawTechnologyDetection: Decodable {
    var technology: String
    var category: String
    var confidence: String
    var signals: [String]
  }

  struct RawCROComponentDetection: Decodable {
    var component: String
    var confidence: String
    var signals: [String]
    var selector: String
  }

  struct RawShopifyThemeIntelligence: Decodable {
    var themeName: String?
    var themeId: Int?
    var themeStoreId: Int?
    var templateType: String?
    var sectionIds: [String]
    var appBlockIds: [String]
  }

  struct RawEcommerceSnapshot: Decodable {
    var priceConsistencyCheck: RawPriceConsistency?
    var cartPriceConsistencyCheck: RawCartPriceConsistency?
    var technologyFingerprint: [RawTechnologyDetection]?
    var croComponentClassification: [RawCROComponentDetection]?
    var shopifyThemeIntelligence: RawShopifyThemeIntelligence?
  }

  enum MapError: Error, LocalizedError {
    case invalidJSON
    var errorDescription: String? { "Could not decode the ecommerce intelligence JSON." }
  }

  struct Result {
    var findings: [AuditFinding]
    var technologyDetections: [RawTechnologyDetection]
    var componentDetections: [RawCROComponentDetection]
    var shopifyTheme: RawShopifyThemeIntelligence?
  }

  /// Maps genuinely actionable results (a real PDP-vs-visible or
  /// PDP-vs-cart price mismatch) to `AuditFinding`s, and passes the
  /// informational technology/component detections through unmapped for
  /// a caller to display separately.
  static func map(fromSnapshotJSON json: String, page: String, viewportWidth: Double?, viewportHeight: Double?) throws -> Result {
    guard let data = json.data(using: .utf8) else { throw MapError.invalidJSON }
    let raw = try JSONDecoder().decode(RawEcommerceSnapshot.self, from: data)
    var findings: [AuditFinding] = []

    if let check = raw.priceConsistencyCheck, check.matches == false {
      findings.append(
        AuditFinding(
          title: "Visible price does not match schema price",
          category: "PDP", severity: AuditFinding.DefaultSeverity.high, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: priceMismatchDescription(check),
          recommendation: "Confirm which price is correct and fix the mismatch between the page's structured data (JSON-LD) and its visible price.",
          tags: ["price-consistency", "structured-data"]
        ))
    }

    if let check = raw.cartPriceConsistencyCheck, check.matches == false {
      findings.append(
        AuditFinding(
          title: "Cart price does not match expected PDP price",
          category: "Cart", severity: AuditFinding.DefaultSeverity.high, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: cartPriceMismatchDescription(check),
          recommendation: "Confirm the applied discount and cart total against the product detail page's price.",
          tags: ["price-consistency", "cart"]
        ))
    }

    return Result(
      findings: findings,
      technologyDetections: raw.technologyFingerprint ?? [],
      componentDetections: raw.croComponentClassification ?? [],
      shopifyTheme: raw.shopifyThemeIntelligence
    )
  }

  private static func priceMismatchDescription(_ check: RawPriceConsistency) -> String {
    let schema = check.schemaPrice.map { String(format: "%.2f", $0) } ?? "unknown"
    let visible = check.visiblePrice.map { String(format: "%.2f", $0) } ?? "unknown"
    return "Expected \(schema) but found \(visible)."
  }

  private static func cartPriceMismatchDescription(_ check: RawCartPriceConsistency) -> String {
    let expected = check.expectedCartPrice.map { String(format: "%.2f", $0) } ?? "unknown"
    let actual = check.cartPrice.map { String(format: "%.2f", $0) } ?? "unknown"
    return "Expected cart price \(expected) (PDP price minus discount) but found \(actual)."
  }
}
