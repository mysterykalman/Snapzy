//
//  AccessibilityAuditMapper.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureAudit module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md). Converts the raw JSON a
//  future browser-extension content script's `runAccessibilityAudit()`
//  produces into real AuditFindings — the bridge between a browser-side
//  DOM audit and the shared Audit Finding record shape. This mapper is
//  ready ahead of the content script itself (browser inspection
//  foundation is a later migration phase); it decodes the exact JSON
//  shape the original Capture extension emits, so the extension port
//  can reuse this contract unchanged.
//

import Foundation

enum AccessibilityAuditMapper {
  struct RawHeading: Decodable { var level: Int; var text: String; var tagName: String }
  struct RawHeadingIssue: Decodable { var type: String; var message: String }
  struct RawHeadingOutline: Decodable { var headings: [RawHeading]; var issues: [RawHeadingIssue] }
  struct RawImage: Decodable { var src: String; var isPresentation: Bool; var hasAlt: Bool; var isInsideLink: Bool; var missingAlt: Bool }
  struct RawLink: Decodable { var href: String; var accessibleName: String; var isEmpty: Bool; var isVague: Bool }
  struct RawFormField: Decodable { var tagName: String; var type: String?; var isLabeled: Bool; var isRequired: Bool }
  struct RawDuplicateId: Decodable { var id: String; var count: Int }
  struct RawHtmlLang: Decodable { var lang: String?; var isMissing: Bool }
  struct RawTabIndexElement: Decodable { var tagName: String; var tabIndex: Int }

  struct RawAuditResult: Decodable {
    var headingOutline: RawHeadingOutline
    var images: [RawImage]
    var links: [RawLink]
    var forms: [RawFormField]
    /// Optional: these three small WCAG rule-engine checks are a later
    /// addition to the content script's `runAccessibilityAudit()`
    /// output — kept optional so decoding an older audit JSON shape (or
    /// a hand-built test fixture that only exercises the original four
    /// categories) doesn't fail.
    var duplicateIds: [RawDuplicateId]?
    var htmlLang: RawHtmlLang?
    var positiveTabIndexElements: [RawTabIndexElement]?
  }

  enum MapError: Error, LocalizedError {
    case invalidJSON
    var errorDescription: String? { "Could not decode the accessibility audit JSON." }
  }

  /// One finding per real issue found (heading hierarchy problems,
  /// images missing alt text, empty/vague links, unlabeled form fields)
  /// — never one blanket "page has accessibility issues" finding, so
  /// each is independently reviewable/assignable/dismissable.
  static func mapFindings(fromAuditJSON json: String, page: String, viewportWidth: Double?, viewportHeight: Double?) throws -> [AuditFinding] {
    guard let data = json.data(using: .utf8) else { throw MapError.invalidJSON }
    let raw = try JSONDecoder().decode(RawAuditResult.self, from: data)
    var findings: [AuditFinding] = []

    for issue in raw.headingOutline.issues {
      let severity = issue.type == "missingH1" ? AuditFinding.DefaultSeverity.high : AuditFinding.DefaultSeverity.medium
      findings.append(
        AuditFinding(
          title: issue.type == "missingH1" ? "Missing H1 heading" : "Heading level skipped",
          category: "Accessibility", severity: severity, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: issue.message,
          recommendation: issue.type == "missingH1"
            ? "Add a single, descriptive H1 heading for the page's main content."
            : "Restructure headings so levels descend one step at a time (don't skip from H2 to H4).",
          tags: ["heading-outline"]
        ))
    }

    for image in raw.images where image.missingAlt {
      findings.append(
        AuditFinding(
          title: "Image missing alt text",
          category: "Accessibility", severity: AuditFinding.DefaultSeverity.medium, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: "Image at \(image.src) has no meaningful alt text.",
          evidence: [image.src],
          recommendation: "Add a concise alt attribute describing the image's content or purpose, or mark it role=\"presentation\" if purely decorative.",
          tags: ["images", "alt-text"]
        ))
    }

    for link in raw.links where link.isEmpty || link.isVague {
      findings.append(
        AuditFinding(
          title: link.isEmpty ? "Link has no accessible name" : "Vague link text",
          category: "Accessibility", severity: AuditFinding.DefaultSeverity.medium, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: link.isEmpty
            ? "Link to \(link.href) has no text content or aria-label."
            : "Link to \(link.href) uses the vague text \"\(link.accessibleName)\", unclear out of context (e.g. to a screen-reader user tabbing through a links list).",
          evidence: [link.href],
          recommendation: link.isEmpty
            ? "Add visible text or an aria-label describing the link's destination."
            : "Replace with text that describes the destination on its own, e.g. \"View pricing plans\" instead of \"Click here\".",
          tags: ["links"]
        ))
    }

    for field in raw.forms where !field.isLabeled {
      findings.append(
        AuditFinding(
          title: "Form field missing a label",
          category: "Accessibility", severity: AuditFinding.DefaultSeverity.high, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: "A \(field.tagName)\(field.type.map { " (type=\($0))" } ?? "") field has no associated label.",
          recommendation: "Associate a <label for=\"...\">, wrap the field in a <label>, or add aria-label/aria-labelledby.",
          tags: ["forms", "labels"]
        ))
    }

    for duplicate in raw.duplicateIds ?? [] {
      findings.append(
        AuditFinding(
          title: "Duplicate id attribute",
          category: "Accessibility", severity: AuditFinding.DefaultSeverity.high, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: "The id \"\(duplicate.id)\" is used \(duplicate.count) times on the page.",
          recommendation: "Ensure every id attribute is unique — duplicate ids break for/aria-labelledby/fragment-link references (WCAG 4.1.1).",
          tags: ["duplicate-id", "parsing"]
        ))
    }

    if let htmlLang = raw.htmlLang, htmlLang.isMissing {
      findings.append(
        AuditFinding(
          title: "Missing or empty <html lang> attribute",
          category: "Accessibility", severity: AuditFinding.DefaultSeverity.medium, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: "The page's <html> element has no (or an empty) lang attribute.",
          recommendation: "Add a lang attribute (e.g. lang=\"en\") to <html> so assistive technology can select the right pronunciation/braille table (WCAG 3.1.1).",
          tags: ["language", "html-lang"]
        ))
    }

    for element in raw.positiveTabIndexElements ?? [] {
      findings.append(
        AuditFinding(
          title: "Positive tabindex disrupts natural tab order",
          category: "Accessibility", severity: AuditFinding.DefaultSeverity.medium, page: page,
          viewportWidth: viewportWidth, viewportHeight: viewportHeight,
          finding: "A \(element.tagName) has tabindex=\(element.tabIndex), which reorders it ahead of the page's natural DOM order.",
          recommendation: "Use tabindex=\"0\" (or restructure the DOM order) instead of a positive tabindex value (WCAG 2.4.3).",
          tags: ["tabindex", "keyboard"]
        ))
    }

    return findings
  }
}
