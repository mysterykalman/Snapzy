//
//  AuditReport.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureAudit module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md). Renders a list of
//  AuditFindings as Markdown, static HTML, or a real vector-text PDF for
//  developer handoff.
//

import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Markdown is the simplest, most broadly useful export (pastes directly
/// into an issue tracker/PR description); the PDF path is a real
/// vector-text rendering (via CoreText into a `CGContext` PDF page), not
/// an image of text, so the output is genuinely readable/selectable/
/// searchable.
enum AuditReport {
  /// Renders `findings` as a Markdown document: one H2 section per
  /// finding with its full field set as a definition-style list, plus a
  /// summary table at the top for a quick scan.
  static func renderMarkdown(findings: [AuditFinding], title: String = "Audit Report") -> String {
    var lines: [String] = ["# \(title)", ""]

    lines.append("| Severity | Category | Title | Status |")
    lines.append("|---|---|---|---|")
    for finding in findings {
      lines.append("| \(finding.severity) | \(finding.category) | \(finding.title) | \(finding.status.rawValue) |")
    }
    lines.append("")

    for finding in findings {
      lines.append("## \(finding.title)")
      lines.append("")
      lines.append("- **Severity**: \(finding.severity)")
      lines.append("- **Category**: \(finding.category)")
      lines.append("- **Status**: \(finding.status.rawValue)")
      lines.append("- **Page**: \(finding.page)")
      if let width = finding.viewportWidth, let height = finding.viewportHeight {
        lines.append("- **Viewport**: \(Int(width))×\(Int(height))")
      }
      if !finding.owner.isEmpty { lines.append("- **Owner**: \(finding.owner)") }
      if !finding.tags.isEmpty { lines.append("- **Tags**: \(finding.tags.joined(separator: ", "))") }
      lines.append("")
      lines.append("**Finding**: \(finding.finding)")
      lines.append("")
      if !finding.recommendation.isEmpty {
        lines.append("**Recommendation**: \(finding.recommendation)")
        lines.append("")
      }
      if !finding.expectedImpact.isEmpty {
        lines.append("**Expected impact**: \(finding.expectedImpact)")
        lines.append("")
      }
      if !finding.evidence.isEmpty {
        lines.append("**Evidence**:")
        for item in finding.evidence { lines.append("- \(item)") }
        lines.append("")
      }
    }

    return lines.joined(separator: "\n")
  }

  /// Renders the "issue list" half of a local HTML report as one
  /// self-contained HTML file (inline `<style>`, no external resources,
  /// no server, opens directly from disk in any browser) — a summary
  /// table plus one detail section per finding, the same content shape
  /// `renderMarkdown` produces, just as HTML. Captures/before-after/
  /// responsive-comparison views need real image embedding and are a
  /// separate, larger feature, not attempted here.
  ///
  /// Every finding field is HTML-escaped (`htmlEscape`) before being
  /// written into the document — findings are user-authored text (a
  /// reviewer's own notes), so this is real output-encoding, not
  /// optional hardening: an unescaped `<`/`&`/quote in a finding's own
  /// text could otherwise break the page's markup or, in a worse case,
  /// inject a script tag that runs when the report is later opened.
  static func renderHTML(findings: [AuditFinding], title: String = "Audit Report") -> String {
    var html = """
      <!doctype html>
      <html>
      <head>
      <meta charset="utf-8">
      <title>\(htmlEscape(title))</title>
      <style>
      body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2rem; color: #1a1a1a; }
      table { border-collapse: collapse; width: 100%; margin-bottom: 2rem; }
      th, td { border: 1px solid #ddd; padding: 0.5rem 0.75rem; text-align: left; font-size: 0.9rem; }
      th { background: #f4f4f4; }
      .finding { border-top: 2px solid #eee; padding-top: 1rem; margin-top: 1rem; }
      .field-label { font-weight: 600; }
      .tag { display: inline-block; background: #eef; border-radius: 4px; padding: 0.1rem 0.5rem; margin-right: 0.25rem; font-size: 0.8rem; }
      </style>
      </head>
      <body>
      <h1>\(htmlEscape(title))</h1>
      <table>
      <tr><th>Severity</th><th>Category</th><th>Title</th><th>Status</th></tr>
      """

    for finding in findings {
      html +=
        "<tr><td>\(htmlEscape(finding.severity))</td><td>\(htmlEscape(finding.category))</td><td>\(htmlEscape(finding.title))</td><td>\(htmlEscape(finding.status.rawValue))</td></tr>\n"
    }
    html += "</table>\n"

    for finding in findings {
      html += "<div class=\"finding\">\n"
      html += "<h2>\(htmlEscape(finding.title))</h2>\n"
      html +=
        "<p><span class=\"field-label\">Severity:</span> \(htmlEscape(finding.severity)) &nbsp; <span class=\"field-label\">Category:</span> \(htmlEscape(finding.category)) &nbsp; <span class=\"field-label\">Status:</span> \(htmlEscape(finding.status.rawValue))</p>\n"
      html += "<p><span class=\"field-label\">Page:</span> \(htmlEscape(finding.page))</p>\n"
      if let width = finding.viewportWidth, let height = finding.viewportHeight {
        html += "<p><span class=\"field-label\">Viewport:</span> \(Int(width))×\(Int(height))</p>\n"
      }
      if !finding.owner.isEmpty {
        html += "<p><span class=\"field-label\">Owner:</span> \(htmlEscape(finding.owner))</p>\n"
      }
      if !finding.tags.isEmpty {
        html += "<p>" + finding.tags.map { "<span class=\"tag\">\(htmlEscape($0))</span>" }.joined() + "</p>\n"
      }
      html += "<p><span class=\"field-label\">Finding:</span> \(htmlEscape(finding.finding))</p>\n"
      if !finding.recommendation.isEmpty {
        html += "<p><span class=\"field-label\">Recommendation:</span> \(htmlEscape(finding.recommendation))</p>\n"
      }
      if !finding.expectedImpact.isEmpty {
        html += "<p><span class=\"field-label\">Expected impact:</span> \(htmlEscape(finding.expectedImpact))</p>\n"
      }
      if !finding.evidence.isEmpty {
        html += "<p><span class=\"field-label\">Evidence:</span></p>\n<ul>\n"
        for item in finding.evidence { html += "<li>\(htmlEscape(item))</li>\n" }
        html += "</ul>\n"
      }
      html += "</div>\n"
    }

    html += "</body>\n</html>\n"
    return html
  }

  /// Escapes the five HTML-significant characters — the standard,
  /// minimal set (not a full sanitizer, since this is plain-text content
  /// being embedded, not user-authored HTML being permitted through).
  private static func htmlEscape(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  enum PDFError: Error, LocalizedError {
    case contextCreationFailed
    var errorDescription: String? { "Could not create a PDF rendering context." }
  }

  /// Renders one PDF page per finding, real vector text (CoreText),
  /// letter-sized pages (612×792pt). Deliberately plain — one field per
  /// line — since this is a developer-handoff document meant to be read
  /// and searched, not a marketing-styled report.
  static func renderPDF(findings: [AuditFinding], to url: URL, pageSize: CGSize = CGSize(width: 612, height: 792)) throws {
    guard let consumer = CGDataConsumer(url: url as CFURL) else { throw PDFError.contextCreationFailed }
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw PDFError.contextCreationFailed }

    let margin: CGFloat = 48
    let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 18, nil)
    let headingFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
    let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 11, nil)

    for finding in findings {
      var pageBox = CGRect(origin: .zero, size: pageSize)
      context.beginPage(mediaBox: &pageBox)

      var cursorY = pageSize.height - margin
      func draw(_ text: String, font: CTFont, lineSpacing: CGFloat = 18) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: margin, y: cursorY)
        CTLineDraw(line, context)
        cursorY -= lineSpacing
      }

      draw(finding.title, font: titleFont, lineSpacing: 28)
      draw("\(finding.severity) · \(finding.category) · \(finding.status.rawValue)", font: headingFont)
      draw("Page: \(finding.page)", font: bodyFont)
      if let width = finding.viewportWidth, let height = finding.viewportHeight {
        draw("Viewport: \(Int(width))×\(Int(height))", font: bodyFont)
      }
      cursorY -= 10
      draw("Finding:", font: headingFont)
      draw(finding.finding, font: bodyFont)
      if !finding.recommendation.isEmpty {
        cursorY -= 10
        draw("Recommendation:", font: headingFont)
        draw(finding.recommendation, font: bodyFont)
      }
      if !finding.owner.isEmpty {
        cursorY -= 10
        draw("Owner: \(finding.owner)", font: bodyFont)
      }

      context.endPage()
    }

    // A findings list with zero items still produces a valid
    // (empty-of-content, single blank) PDF rather than a malformed
    // zero-page file some readers reject.
    if findings.isEmpty {
      var pageBox = CGRect(origin: .zero, size: pageSize)
      context.beginPage(mediaBox: &pageBox)
      context.endPage()
    }

    context.closePDF()
  }

  /// Reads the *actual rendered text* back out of a PDF produced by
  /// `renderPDF` — real verification (via PDFKit's text extraction) that
  /// this is genuine selectable/searchable vector text, not a rasterized
  /// image of text.
  static func extractText(from url: URL) -> String {
    guard let document = PDFDocument(url: url) else { return "" }
    return document.string ?? ""
  }
}
