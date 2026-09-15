//
//  BrowserBridgeCoordinatorRoutingTests.swift
//  SnapzyTests
//
//  Verifies BrowserBridgeCoordinator.route dispatches real inspection
//  message types to InspectionFindingsStore (decoding via
//  AccessibilityAuditMapper/EcommerceAuditMapper), falling back to
//  BridgeInfrastructureRouter for everything else. Exercises `route`
//  directly rather than through the real socket server -- that
//  end-to-end transport path is already covered by
//  BrowserBridgeCoordinatorTests.
//

import BrowserBridgeKit
import XCTest
@testable import Snapzy

@MainActor
final class BrowserBridgeCoordinatorRoutingTests: XCTestCase {

  override func tearDown() async throws {
    InspectionFindingsStore.shared.clear()
    try await super.tearDown()
  }

  private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) {
    let expectation = expectation(description: "condition met")
    let start = Date()
    func poll() {
      if condition() || Date().timeIntervalSince(start) > timeout {
        expectation.fulfill()
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }
    poll()
    wait(for: [expectation], timeout: timeout + 1)
  }

  func testUnrecognizedInfrastructureTypeStillFallsThroughToInfrastructureRouter() {
    let response = BrowserBridgeCoordinator.route(BridgeMessage(type: "ping"), appVersion: nil)
    XCTAssertTrue(response.ok)
    XCTAssertEqual(response.payload, .object(["pong": .bool(true)]))
  }

  func testAccessibilityAuditResultDecodesIntoInspectionFindingsStore() {
    let auditJSON = """
      {"headingOutline":{"headings":[],"issues":[{"type":"missingH1","message":"No H1 heading found on the page."}]},"images":[],"links":[],"forms":[]}
      """
    let message = BridgeMessage(
      type: "accessibility.audit.result",
      payload: .object([
        "url": .string("https://example.com/pricing"),
        "auditJSON": .string(auditJSON),
        "viewportWidth": .number(1440),
        "viewportHeight": .number(900),
      ])
    )

    let response = BrowserBridgeCoordinator.route(message, appVersion: nil)
    XCTAssertTrue(response.ok)

    waitUntil { InspectionFindingsStore.shared.findings.count == 1 }
    let finding = InspectionFindingsStore.shared.findings.first
    XCTAssertEqual(finding?.title, "Missing H1 heading")
    XCTAssertEqual(finding?.page, "https://example.com/pricing")
    XCTAssertEqual(finding?.viewportWidth, 1440)
  }

  func testEcommerceAuditResultDecodesIntoInspectionFindingsStore() {
    let snapshotJSON = """
      {"priceConsistencyCheck":{"schemaPrice":19.99,"visiblePrice":24.99,"matches":false}}
      """
    let message = BridgeMessage(
      type: "ecommerce.audit.result",
      payload: .object([
        "url": .string("https://example.com/product/widget"),
        "snapshotJSON": .string(snapshotJSON),
      ])
    )

    let response = BrowserBridgeCoordinator.route(message, appVersion: nil)
    XCTAssertTrue(response.ok)

    waitUntil { InspectionFindingsStore.shared.findings.count == 1 }
    let finding = InspectionFindingsStore.shared.findings.first
    XCTAssertEqual(finding?.title, "Visible price does not match schema price")
    XCTAssertEqual(finding?.category, "PDP")
  }

  func testAccessibilityAuditResultMissingRequiredKeysFails() {
    let message = BridgeMessage(type: "accessibility.audit.result", payload: .object(["url": .string("https://example.com")]))
    let response = BrowserBridgeCoordinator.route(message, appVersion: nil)
    XCTAssertFalse(response.ok)
    XCTAssertEqual(response.error?.code, BridgeErrorCode.invalidMessage)
  }
}
