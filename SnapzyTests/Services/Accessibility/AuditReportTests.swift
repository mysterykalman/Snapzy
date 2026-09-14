//
//  AuditReportTests.swift
//  SnapzyTests
//
//  Verifies real rendered output: the PDF path writes an actual file and
//  reads its text back via PDFKit; HTML/Markdown checks assert on real
//  string content and escaping, not just "didn't crash."
//

import XCTest
@testable import Snapzy

final class AuditReportTests: XCTestCase {

  private func sampleFinding(title: String = "Missing alt text", evidence: [String] = ["/hero.jpg"]) -> AuditFinding {
    AuditFinding(
      title: title, category: "Accessibility", severity: AuditFinding.DefaultSeverity.high, page: "https://example.com",
      viewportWidth: 1440, viewportHeight: 900, finding: "The hero image has no alt text.",
      evidence: evidence, recommendation: "Add a descriptive alt attribute.", owner: "Jane"
    )
  }

  func testMarkdownIncludesEveryPopulatedField() {
    let markdown = AuditReport.renderMarkdown(findings: [sampleFinding()], title: "Storefront Audit")
    XCTAssertTrue(markdown.contains("# Storefront Audit"))
    XCTAssertTrue(markdown.contains("Missing alt text"))
    XCTAssertTrue(markdown.contains("**Recommendation**: Add a descriptive alt attribute."))
    XCTAssertTrue(markdown.contains("**Owner**: Jane"))
    XCTAssertTrue(markdown.contains("/hero.jpg"))
  }

  func testMarkdownOmitsEmptyOptionalFieldsRatherThanPrintingBlankLines() {
    let bareFinding = AuditFinding(title: "Bare finding", category: "Accessibility", severity: "Low", page: "https://example.com", finding: "Something minor.")
    let markdown = AuditReport.renderMarkdown(findings: [bareFinding])
    XCTAssertFalse(markdown.contains("**Recommendation**:"))
    XCTAssertFalse(markdown.contains("**Evidence**:"))
  }

  func testHTMLEscapesUserAuthoredText() {
    let maliciousFinding = AuditFinding(
      title: "<script>alert(1)</script>", category: "Accessibility", severity: "High", page: "https://example.com",
      finding: "Contains \"quotes\" & <tags>"
    )
    let html = AuditReport.renderHTML(findings: [maliciousFinding])
    XCTAssertFalse(html.contains("<script>alert(1)</script>"))
    XCTAssertTrue(html.contains("&lt;script&gt;"))
    XCTAssertTrue(html.contains("&amp;"))
    XCTAssertTrue(html.contains("&quot;quotes&quot;"))
  }

  func testHTMLIsAWellFormedSelfContainedDocument() {
    let html = AuditReport.renderHTML(findings: [sampleFinding()], title: "Report")
    XCTAssertTrue(html.hasPrefix("<!doctype html>"))
    XCTAssertTrue(html.contains("<style>"))
    XCTAssertTrue(html.hasSuffix("</html>\n"))
  }

  func testPDFWritesARealFileWithSelectableTextPerFinding() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("audit-report-test-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }

    let findings = [sampleFinding(title: "Finding A"), sampleFinding(title: "Finding B")]
    try AuditReport.renderPDF(findings: findings, to: url)

    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    let extractedText = AuditReport.extractText(from: url)
    XCTAssertTrue(extractedText.contains("Finding A"))
    XCTAssertTrue(extractedText.contains("Finding B"))
    XCTAssertTrue(extractedText.contains("Add a descriptive alt attribute."))
  }

  func testPDFWithNoFindingsStillProducesAValidSinglePageDocument() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("audit-report-empty-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }

    try AuditReport.renderPDF(findings: [], to: url)

    let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
    XCTAssertEqual(document.numberOfPages, 1)
  }
}
