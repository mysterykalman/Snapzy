//
//  InspectionFindingsStore.swift
//  Snapzy
//
//  Where AuditFindings decoded from real browser-extension audit
//  results (accessibility.audit.result / ecommerce.audit.result, routed
//  in BrowserBridgeCoordinator) land once they arrive over the bridge --
//  the first thing to actually consume AccessibilityAuditMapper/
//  EcommerceAuditMapper output. In-memory only for now (findings are
//  transient inspection results tied to the current browsing session,
//  not persisted capture history); a future Inspection Results window
//  reads this store to display them.
//

import Combine
import Foundation

@MainActor
final class InspectionFindingsStore: ObservableObject {
  static let shared = InspectionFindingsStore()

  @Published private(set) var findings: [AuditFinding] = []
  @Published private(set) var technologyDetections: [EcommerceAuditMapper.RawTechnologyDetection] = []
  @Published private(set) var componentDetections: [EcommerceAuditMapper.RawCROComponentDetection] = []

  private init() {}

  // Every class implicitly picks up this project's
  // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor build setting; without an
  // explicit deinit the compiler synthesizes an isolated one that hits a
  // Swift runtime bug on deallocation of a non-singleton instance (see
  // DatabaseManager.swift for the full writeup). Only ever used via
  // `.shared`, but free insurance against a future transient instance
  // (e.g. in a test) hitting the same bug.
  nonisolated deinit {}

  @discardableResult
  func addAccessibilityAudit(json: String, page: String, viewportWidth: Double?, viewportHeight: Double?) throws -> [AuditFinding] {
    let newFindings = try AccessibilityAuditMapper.mapFindings(
      fromAuditJSON: json, page: page, viewportWidth: viewportWidth, viewportHeight: viewportHeight
    )
    findings.append(contentsOf: newFindings)
    return newFindings
  }

  @discardableResult
  func addEcommerceAudit(json: String, page: String, viewportWidth: Double?, viewportHeight: Double?) throws -> [AuditFinding] {
    let result = try EcommerceAuditMapper.map(
      fromSnapshotJSON: json, page: page, viewportWidth: viewportWidth, viewportHeight: viewportHeight
    )
    findings.append(contentsOf: result.findings)
    technologyDetections.append(contentsOf: result.technologyDetections)
    componentDetections.append(contentsOf: result.componentDetections)
    return result.findings
  }

  func clear() {
    findings.removeAll()
    technologyDetections.removeAll()
    componentDetections.removeAll()
  }
}
