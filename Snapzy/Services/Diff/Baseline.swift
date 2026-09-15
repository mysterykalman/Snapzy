//
//  Baseline.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureDiff module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md), adapted to persist via
//  Snapzy's existing GRDB-backed DatabaseManager (see BaselineStore.swift)
//  rather than the original's separate hand-rolled SQLite3-C-API store --
//  GRDB is already a proven, working dependency in this codebase (see
//  CaptureHistoryRecord.swift for the identical FetchableRecord/
//  PersistableRecord-via-Codable pattern followed here), so a second,
//  independent SQLite file/API for one more pair of tables would just be
//  duplicated infrastructure.
//
//  "Any capture can become a baseline" -- this models a baseline as a
//  reference back to a capture's history record (by id, not a copy of
//  the image itself, matching Snapzy's own existing non-duplicating
//  history storage) plus the comparison bookkeeping: a change
//  threshold, and an approval state that's tracked per comparison
//  rather than assumed. Actually producing the reference capture's
//  CGImage for a real diff is the caller's job (loading the history
//  record's source media) -- this type only tracks which capture a
//  comparison is against and what was decided about it.
//

import Foundation
import GRDB

struct Baseline: Codable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
  var id: UUID
  var name: String
  var createdAt: Date
  /// The capture this baseline references -- a history record id, not
  /// a duplicated image.
  var sourceCaptureID: UUID
  var viewportWidth: Double?
  var viewportHeight: Double?

  init(
    id: UUID = UUID(),
    name: String,
    createdAt: Date = Date(),
    sourceCaptureID: UUID,
    viewportWidth: Double? = nil,
    viewportHeight: Double? = nil
  ) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.sourceCaptureID = sourceCaptureID
    self.viewportWidth = viewportWidth
    self.viewportHeight = viewportHeight
  }
}

/// Change threshold per baseline: exact / percentage / perceptual
/// sensitivity.
enum ChangeThreshold: Codable, Equatable {
  /// Any pixel difference at all fails the comparison.
  case exact
  /// Fails once the differing-pixel ratio (0...1, as `ImageDiff.Result`
  /// reports it) exceeds this fraction.
  case percentage(Double)
  /// Fails once `ImageDiff.perceptualDiff`'s differing-ratio exceeds
  /// this fraction, using perceptual (block-averaged) comparison rather
  /// than exact pixels.
  case perceptual(Double)

  /// Whether a comparison with the given `ImageDiff.Result` counts as a
  /// pass (no meaningful change) under this threshold.
  func passes(differingRatio: Double) -> Bool {
    switch self {
    case .exact: return differingRatio == 0
    case .percentage(let maxRatio): return differingRatio <= maxRatio
    case .perceptual(let maxRatio): return differingRatio <= maxRatio
    }
  }
}

/// Baseline approval states: unreviewed / approved / changed
/// intentionally / regression / ignored.
enum BaselineApprovalState: String, Codable, Equatable {
  case unreviewed
  case approved
  case changedIntentionally
  case regression
  case ignored
}

/// One comparison of a new capture against a `Baseline` -- every
/// approved baseline stays versioned: this is the versioned comparison
/// record, not a mutation of the baseline itself, so history of every
/// past comparison against a given baseline is preserved.
struct BaselineComparison: Codable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
  var id: UUID
  var baselineID: UUID
  var comparedCaptureID: UUID
  var comparedAt: Date
  var differingRatio: Double
  var threshold: ChangeThreshold
  var approvalState: BaselineApprovalState

  init(
    id: UUID = UUID(),
    baselineID: UUID,
    comparedCaptureID: UUID,
    comparedAt: Date = Date(),
    differingRatio: Double,
    threshold: ChangeThreshold,
    approvalState: BaselineApprovalState = .unreviewed
  ) {
    self.id = id
    self.baselineID = baselineID
    self.comparedCaptureID = comparedCaptureID
    self.comparedAt = comparedAt
    self.differingRatio = differingRatio
    self.threshold = threshold
    self.approvalState = approvalState
  }

  /// Whether this comparison's actual differing ratio falls within its
  /// own threshold -- independent of `approvalState`, which is a human
  /// decision that may override this (e.g. a real difference marked
  /// `.changedIntentionally` rather than `.regression`).
  var passesThreshold: Bool {
    threshold.passes(differingRatio: differingRatio)
  }
}
