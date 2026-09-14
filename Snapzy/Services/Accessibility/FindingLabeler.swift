//
//  FindingLabeler.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureAudit module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md). Auto-numbers findings
//  into visible counter labels (e.g. PDP-01, NAV-01) for annotating
//  evidence screenshots.
//

import Foundation

/// A pure `category -> next label` function. Kept separate from any
/// annotation/counter-rendering code so this module has no dependency on
/// the editor.
enum FindingLabeler {
  /// Sensible abbreviations for the default category list
  /// (`AuditFinding.DefaultCategory.all`) — several are already short
  /// enough to use as-is (PDP/PLP/SEO), the others get a worked-example
  /// style (`Navigation` → `NAV`). A category outside this list (categories
  /// are explicitly configurable/user-defined) falls back to its own
  /// first four letters, uppercased — a reasonable default a user can
  /// still visually recognize, not a crash or an empty label.
  private static let abbreviations: [String: String] = [
    "Navigation": "NAV", "Homepage": "HOME", "PLP": "PLP", "PDP": "PDP",
    "Search": "SEARCH", "Recommendations": "REC", "Cart": "CART",
    "Checkout": "CHECKOUT", "Accessibility": "A11Y", "Performance": "PERF",
    "SEO": "SEO", "Analytics": "ANALYTICS", "Merchandising": "MERCH", "Content": "CONTENT",
  ]

  static func abbreviation(for category: AuditFinding.Category) -> String {
    if let known = abbreviations[category] { return known }
    let letters = category.uppercased().filter { $0.isLetter || $0.isNumber }
    return letters.isEmpty ? "MISC" : String(letters.prefix(4))
  }

  /// The next sequential label for `category` given `existingLabels`
  /// already assigned within this same audit (e.g. previously generated
  /// `nextLabel` results, tracked by the caller — this function is pure
  /// and doesn't read/write `AuditFinding.tags` itself, so a caller
  /// decides where to actually store the result). Real, exact number
  /// continuity: passing back every label this function has already
  /// produced for `category` always yields the next integer in sequence,
  /// never reusing or skipping one, even if `existingLabels` arrives in
  /// an arbitrary order.
  static func nextLabel(for category: AuditFinding.Category, existingLabels: [String]) -> String {
    let prefix = abbreviation(for: category)
    let existingNumbers = existingLabels.compactMap { label -> Int? in
      guard label.hasPrefix(prefix + "-") else { return nil }
      return Int(label.dropFirst(prefix.count + 1))
    }
    let next = (existingNumbers.max() ?? 0) + 1
    return "\(prefix)-" + String(format: "%02d", next)
  }
}
