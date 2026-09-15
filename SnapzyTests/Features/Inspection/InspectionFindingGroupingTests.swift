//
//  InspectionFindingGroupingTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class InspectionFindingGroupingTests: XCTestCase {

  private func makeFinding(
    category: String = "Accessibility",
    severity: String = AuditFinding.DefaultSeverity.high,
    page: String = "https://example.com",
    status: AuditFinding.Status = .open
  ) -> AuditFinding {
    AuditFinding(
      title: "Test finding", category: category, severity: severity, status: status,
      page: page, finding: "Something is wrong"
    )
  }

  func testSeverityKeyReturnsTheFindingsSeverity() {
    let finding = makeFinding(severity: AuditFinding.DefaultSeverity.critical)
    XCTAssertEqual(InspectionFindingGrouping.severity.key(for: finding), AuditFinding.DefaultSeverity.critical)
  }

  func testCategoryKeyReturnsTheFindingsCategory() {
    let finding = makeFinding(category: "PDP")
    XCTAssertEqual(InspectionFindingGrouping.category.key(for: finding), "PDP")
  }

  func testPageKeyReturnsTheFindingsPage() {
    let finding = makeFinding(page: "https://example.com/cart")
    XCTAssertEqual(InspectionFindingGrouping.page.key(for: finding), "https://example.com/cart")
  }

  func testStatusKeyReturnsTheFindingsStatusRawValue() {
    let finding = makeFinding(status: .resolved)
    XCTAssertEqual(InspectionFindingGrouping.status.key(for: finding), "resolved")
  }

  func testSeverityHasAPreferredOrderMatchingDefaultSeverities() {
    XCTAssertEqual(InspectionFindingGrouping.severity.preferredOrder, AuditFinding.DefaultSeverity.all)
  }

  func testCategoryPageAndStatusHaveNoPreferredOrder() {
    XCTAssertNil(InspectionFindingGrouping.category.preferredOrder)
    XCTAssertNil(InspectionFindingGrouping.page.preferredOrder)
    XCTAssertNil(InspectionFindingGrouping.status.preferredOrder)
  }
}
