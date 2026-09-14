//
//  AuditFinding.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureAudit module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md). A shared audit-finding
//  record shape used by the accessibility audit now, and intended for
//  future ecommerce/CRO and visual-QA findings — not something each
//  audit feature should reinvent.
//

import Foundation

struct AuditFinding: Codable, Equatable, Identifiable {
  /// A configurable severity taxonomy: this stays a plain string rather
  /// than a fixed enum (a user-defined taxonomy must be representable
  /// too), with the five default values available as constants for a
  /// picker UI to offer.
  typealias Severity = String
  enum DefaultSeverity {
    static let critical: Severity = "Critical"
    static let high: Severity = "High"
    static let medium: Severity = "Medium"
    static let low: Severity = "Low"
    static let opportunity: Severity = "Opportunity"
    static let all: [Severity] = [critical, high, medium, low, opportunity]
  }

  /// A default category list — again a plain string, not a fixed enum,
  /// since ecommerce audits are expected to introduce project-specific
  /// categories beyond this default set.
  typealias Category = String
  enum DefaultCategory {
    static let all: [Category] = [
      "Navigation", "Homepage", "PLP", "PDP", "Search", "Recommendations",
      "Cart", "Checkout", "Accessibility", "Performance", "SEO", "Analytics",
      "Merchandising", "Content",
    ]
  }

  enum Status: String, Codable, Equatable, CaseIterable {
    case open
    case inProgress
    case resolved
    case wontFix
    case duplicate
  }

  var id: UUID
  var title: String
  var category: Category
  var severity: Severity
  var status: Status
  var page: String
  var viewportWidth: Double?
  var viewportHeight: Double?
  /// A reference to a saved capture (history record id), not an
  /// embedded image — matches Snapzy's existing non-duplicating storage
  /// principle for history/media.
  var screenshotCaptureID: UUID?
  var elementAnchor: ElementLocator?
  var finding: String
  /// Free-form evidence references (a capture id, a file path, a short
  /// description) rather than a fixed evidence-type enum, since more
  /// evidence kinds will likely be added as later audit phases land.
  var evidence: [String]
  var recommendation: String
  var expectedImpact: String
  var owner: String
  var tags: [String]
  var createdAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    category: Category,
    severity: Severity,
    status: Status = .open,
    page: String,
    viewportWidth: Double? = nil,
    viewportHeight: Double? = nil,
    screenshotCaptureID: UUID? = nil,
    elementAnchor: ElementLocator? = nil,
    finding: String,
    evidence: [String] = [],
    recommendation: String = "",
    expectedImpact: String = "",
    owner: String = "",
    tags: [String] = [],
    createdAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.category = category
    self.severity = severity
    self.status = status
    self.page = page
    self.viewportWidth = viewportWidth
    self.viewportHeight = viewportHeight
    self.screenshotCaptureID = screenshotCaptureID
    self.elementAnchor = elementAnchor
    self.finding = finding
    self.evidence = evidence
    self.recommendation = recommendation
    self.expectedImpact = expectedImpact
    self.owner = owner
    self.tags = tags
    self.createdAt = createdAt
  }
}
