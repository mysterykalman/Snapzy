//
//  BaselineStoreTests.swift
//  SnapzyTests
//
//  Real round-trip tests against an actual GRDB database file (via
//  DatabaseManager.openDatabase(at:), which runs the full migrator
//  including the baseline/baselineComparison tables) -- not a mock.
//
//  HISTORICAL NOTE: these tests originally crashed the CI runner's
//  hosted test process deterministically. Root-caused via real
//  symbolicated .ips crash reports (captured by a temporary CI
//  diagnostic workflow, since this environment has no local
//  Xcode/lldb) to the exact same Swift runtime bug already fixed once
//  this session for BrowserBridgeCoordinator: with this project's
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor build setting, a class
//  with no explicit deinit gets a compiler-synthesized isolated
//  deinit, and swift_task_deinitOnExecutorMainActorBackDeploy
//  corrupts the heap when a *transient* (non-singleton) instance is
//  deallocated. setUpWithError() below creates exactly such a
//  transient DatabaseManager via openDatabase(at:), which goes out of
//  scope at the end of the method. Fixed by adding
//  `nonisolated deinit {}` to DatabaseManager (see DatabaseManager.swift).
//  Verified fixed via the same diagnostic workflow: all 8 tests now
//  run to completion with no crash report generated.
//

import Foundation
import XCTest
@testable import Snapzy

final class BaselineStoreTests: XCTestCase {

  private var testDirectory: URL!
  private var store: BaselineStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    testDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_BaselineStore_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    let manager = try DatabaseManager.openDatabase(at: testDirectory.appendingPathComponent("snapzy.db"))
    store = BaselineStore(dbPool: manager.dbPool)
  }

  override func tearDownWithError() throws {
    if let testDirectory {
      try? FileManager.default.removeItem(at: testDirectory)
    }
    try super.tearDownWithError()
  }

  func testSaveAndFetchBaselineRoundTrips() throws {
    // A fixed createdAt (rather than the default Date()) avoids a false
    // failure from GRDB's millisecond-resolution date storage being
    // unable to round-trip Date()'s sub-millisecond precision exactly.
    let baseline = Baseline(name: "Homepage hero", createdAt: Date(timeIntervalSince1970: 1_700_000_000), sourceCaptureID: UUID(), viewportWidth: 1440, viewportHeight: 900)
    try store.save(baseline)

    let fetched = try store.baseline(id: baseline.id)
    XCTAssertEqual(fetched, baseline)
  }

  func testAllBaselinesOrdersByCreatedAtDescending() throws {
    let older = Baseline(name: "Older", createdAt: Date(timeIntervalSince1970: 1000), sourceCaptureID: UUID())
    let newer = Baseline(name: "Newer", createdAt: Date(timeIntervalSince1970: 2000), sourceCaptureID: UUID())
    try store.save(older)
    try store.save(newer)

    let all = try store.allBaselines()
    XCTAssertEqual(all.map(\.name), ["Newer", "Older"])
  }

  func testDeleteBaselineRemovesItAndItsComparisons() throws {
    let baseline = Baseline(name: "To delete", sourceCaptureID: UUID())
    try store.save(baseline)
    let comparison = BaselineComparison(baselineID: baseline.id, comparedCaptureID: UUID(), differingRatio: 0.02, threshold: .percentage(0.05))
    try store.save(comparison)

    try store.deleteBaseline(id: baseline.id)

    XCTAssertNil(try store.baseline(id: baseline.id))
    XCTAssertTrue(try store.comparisons(forBaselineID: baseline.id).isEmpty)
  }

  func testSaveAndFetchComparisonRoundTripsEveryThresholdKind() throws {
    let baseline = Baseline(name: "Thresholds", sourceCaptureID: UUID())
    try store.save(baseline)

    let exact = BaselineComparison(baselineID: baseline.id, comparedCaptureID: UUID(), differingRatio: 0, threshold: .exact)
    let percentage = BaselineComparison(baselineID: baseline.id, comparedCaptureID: UUID(), differingRatio: 0.03, threshold: .percentage(0.05))
    let perceptual = BaselineComparison(baselineID: baseline.id, comparedCaptureID: UUID(), differingRatio: 0.1, threshold: .perceptual(0.15))
    try store.save(exact)
    try store.save(percentage)
    try store.save(perceptual)

    let fetched = try store.comparisons(forBaselineID: baseline.id)
    XCTAssertEqual(fetched.count, 3)
    XCTAssertTrue(fetched.contains { $0.threshold == .exact })
    XCTAssertTrue(fetched.contains { $0.threshold == .percentage(0.05) })
    XCTAssertTrue(fetched.contains { $0.threshold == .perceptual(0.15) })
  }

  func testComparisonsOrderedMostRecentFirst() throws {
    let baseline = Baseline(name: "Ordering", sourceCaptureID: UUID())
    try store.save(baseline)

    let older = BaselineComparison(baselineID: baseline.id, comparedCaptureID: UUID(), comparedAt: Date(timeIntervalSince1970: 1000), differingRatio: 0, threshold: .exact)
    let newer = BaselineComparison(baselineID: baseline.id, comparedCaptureID: UUID(), comparedAt: Date(timeIntervalSince1970: 2000), differingRatio: 0, threshold: .exact)
    try store.save(older)
    try store.save(newer)

    let fetched = try store.comparisons(forBaselineID: baseline.id)
    XCTAssertEqual(fetched.map(\.id), [newer.id, older.id])
  }

  func testUpdateApprovalStateChangesOnlyThatField() throws {
    let baseline = Baseline(name: "Approval", sourceCaptureID: UUID())
    try store.save(baseline)
    let comparison = BaselineComparison(baselineID: baseline.id, comparedCaptureID: UUID(), differingRatio: 0.2, threshold: .percentage(0.05))
    try store.save(comparison)
    XCTAssertEqual(comparison.approvalState, .unreviewed)

    try store.updateApprovalState(comparisonID: comparison.id, to: .changedIntentionally)

    let fetched = try store.comparisons(forBaselineID: baseline.id)
    XCTAssertEqual(fetched.first?.approvalState, .changedIntentionally)
    XCTAssertEqual(fetched.first?.differingRatio, 0.2)
  }

  func testChangeThresholdPassesLogic() {
    XCTAssertTrue(ChangeThreshold.exact.passes(differingRatio: 0))
    XCTAssertFalse(ChangeThreshold.exact.passes(differingRatio: 0.001))
    XCTAssertTrue(ChangeThreshold.percentage(0.05).passes(differingRatio: 0.05))
    XCTAssertFalse(ChangeThreshold.percentage(0.05).passes(differingRatio: 0.051))
  }

  func testBaselineComparisonPassesThresholdReflectsItsOwnData() {
    let passing = BaselineComparison(baselineID: UUID(), comparedCaptureID: UUID(), differingRatio: 0.01, threshold: .percentage(0.05))
    let failing = BaselineComparison(baselineID: UUID(), comparedCaptureID: UUID(), differingRatio: 0.2, threshold: .percentage(0.05))
    XCTAssertTrue(passing.passesThreshold)
    XCTAssertFalse(failing.passesThreshold)
  }
}
