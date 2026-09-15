//
//  BaselineStore.swift
//  Snapzy
//
//  Adapted from the original Capture app's CaptureDiff/BaselineStore.swift
//  (owned by the user; see docs/REFERENCE_PROVENANCE.md). The original
//  hand-rolled a separate SQLite3-C-API-backed store; this instead uses
//  Snapzy's existing GRDB-backed DatabaseManager (the "baseline"/
//  "baselineComparison" tables added in DatabaseManager's migrator),
//  following the exact pattern CaptureHistoryStore already establishes
//  for reading/writing GRDB records -- including its optional-`dbPool`/
//  graceful-degradation shape, so a database-initialization failure
//  elsewhere doesn't crash this unrelated feature. A second independent
//  database file for two more tables would just be duplicated
//  infrastructure Snapzy already has a working, tested version of.
//

import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "BaselineStore")

final class BaselineStore: @unchecked Sendable {
  static let shared = BaselineStore()

  enum StoreError: LocalizedError {
    case databaseUnavailable
    var errorDescription: String? { "The baseline database is unavailable." }
  }

  private let dbPool: DatabasePool?

  init(dbPool: DatabasePool? = nil) {
    if let dbPool {
      self.dbPool = dbPool
    } else {
      do {
        self.dbPool = try DatabaseManager.shared().dbPool
      } catch {
        self.dbPool = nil
        logger.error("Baseline persistence disabled; database unavailable: \(error.localizedDescription)")
      }
    }
  }

  private func requirePool() throws -> DatabasePool {
    guard let dbPool else { throw StoreError.databaseUnavailable }
    return dbPool
  }

  // MARK: - Baselines

  func save(_ baseline: Baseline) throws {
    try requirePool().write { db in
      try baseline.save(db)
    }
  }

  func allBaselines() throws -> [Baseline] {
    try requirePool().read { db in
      try Baseline.order(Column("createdAt").desc).fetchAll(db)
    }
  }

  func baseline(id: UUID) throws -> Baseline? {
    try requirePool().read { db in
      try Baseline.fetchOne(db, id: id)
    }
  }

  func deleteBaseline(id: UUID) throws {
    try requirePool().write { db in
      _ = try Baseline.deleteOne(db, id: id)
      try db.execute(sql: "DELETE FROM baselineComparison WHERE baselineID = ?", arguments: [id])
    }
  }

  // MARK: - Comparisons

  func save(_ comparison: BaselineComparison) throws {
    try requirePool().write { db in
      try comparison.save(db)
    }
  }

  /// Every comparison ever made against `baselineID`, most recent
  /// first -- every approved baseline stays versioned: this is what
  /// makes that real, a full retained history rather than just the
  /// latest comparison overwriting the last.
  func comparisons(forBaselineID baselineID: UUID) throws -> [BaselineComparison] {
    try requirePool().read { db in
      try BaselineComparison
        .filter(Column("baselineID") == baselineID)
        .order(Column("comparedAt").desc)
        .fetchAll(db)
    }
  }

  /// Updates just the approval state of an existing comparison -- a
  /// human review decision (unreviewed / approved / changed
  /// intentionally / regression / ignored), independent of the
  /// comparison's own measured `differingRatio`/`threshold`.
  func updateApprovalState(comparisonID: UUID, to state: BaselineApprovalState) throws {
    try requirePool().write { db in
      try db.execute(
        sql: "UPDATE baselineComparison SET approvalState = ? WHERE id = ?",
        arguments: [state.rawValue, comparisonID]
      )
    }
  }
}
