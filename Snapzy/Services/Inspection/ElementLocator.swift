//
//  ElementLocator.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureInspection module
//  (owned by the user; see docs/REFERENCE_PROVENANCE.md). Shared by the
//  future browser-inspection subsystem (element evidence captured via
//  BrowserBridge) and the accessibility/ecommerce audit findings that
//  anchor a finding to a specific page element.
//

import Foundation

/// Ranked locator candidates for robust element re-identification.
/// `primary` is the strategy the extension had the most confidence in at
/// capture time; `candidates` are the fallback chain in priority order,
/// strongest first.
struct ElementLocator: Codable, Equatable {
  enum Strategy: String, Codable, CaseIterable, Sendable {
    case dataTestID
    case stableID
    case roleAndAccessibleName
    case semanticAttributes
    case classAndStructure
    case textFingerprint
    case ancestryFingerprint
    case absoluteDOMPath

    /// Priority order, strongest/most-stable first.
    static let priorityOrder: [Strategy] = [
      .dataTestID, .stableID, .roleAndAccessibleName, .semanticAttributes,
      .classAndStructure, .textFingerprint, .ancestryFingerprint, .absoluteDOMPath,
    ]
  }

  struct Candidate: Codable, Equatable {
    var strategy: Strategy
    var value: String
  }

  var candidates: [Candidate]

  /// The strongest available candidate, per the fixed priority order —
  /// this is what a re-capture attempt should try first.
  var primary: Candidate? {
    for strategy in Strategy.priorityOrder {
      if let match = candidates.first(where: { $0.strategy == strategy }) {
        return match
      }
    }
    return nil
  }
}
