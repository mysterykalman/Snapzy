//
//  SmartRedact.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureCore module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md), adapted to use CGRect
//  directly rather than Capture's own Region wrapper type (Snapzy has no
//  equivalent abstraction elsewhere, so introducing one here would be
//  unused indirection).
//

import CoreGraphics

/// On-device detector that proposes redactions for likely-sensitive
/// strings; the user still approves each one. Combines
/// `PrivacyPreflight`'s pattern detection with per-line OCR bounding
/// boxes to propose a real *region* to redact per finding, not just a
/// text match.
enum SmartRedact {
  struct Proposal: Equatable {
    var category: PrivacyPreflight.Category
    var text: String
    var region: CGRect
  }

  /// Runs `PrivacyPreflight` independently over *each* recognized line's
  /// own text, rather than one concatenated block — a match's real
  /// bounding box is only directly knowable from the single line it was
  /// actually recognized within. A real, documented limitation this
  /// implies: a sensitive pattern that happens to span two separately-
  /// recognized lines is not detected — a rare case for these patterns
  /// (email/phone/credit-card/API-key/IP), which are normally short
  /// enough to land on one line, but a real gap nonetheless rather than
  /// a silently-assumed-solved one.
  static func proposeRedactions(
    observations: [(text: String, boundingBox: CGRect)], confidentialTerms: [String] = []
  ) -> [Proposal] {
    var proposals: [Proposal] = []
    for observation in observations {
      let matches = PrivacyPreflight.scan(observation.text, confidentialTerms: confidentialTerms)
      for match in matches {
        proposals.append(Proposal(category: match.category, text: match.text, region: observation.boundingBox))
      }
    }
    return proposals
  }
}
