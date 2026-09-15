//
//  PageLayoutDiff.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureDiff module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//
//  "Layout" diff mode (ignore changing text/image content, focus on
//  position/size/spacing/arrangement -- critical for ecommerce pages with
//  naturally changing prices/products), applied across a whole page's
//  worth of elements rather than one element at a time (`ElementDiff`
//  handles the single-element case). Two snapshots -- each a list of
//  `ElementEvidence` captured across the same page -- are matched up by
//  locator so an element that merely moved/resized is distinguished from
//  one that was actually added or removed, and content changes (a
//  product's title text, a changing price) are ignored entirely since
//  only `rect` is compared.
//

import Foundation

struct LayoutChange: Equatable, Identifiable {
  enum Kind: Equatable {
    case unchanged
    case moved(dx: Double, dy: Double)
    case resized(dWidth: Double, dHeight: Double)
    case movedAndResized(dx: Double, dy: Double, dWidth: Double, dHeight: Double)
    case added
    case removed
  }

  var id: UUID
  var before: ElementEvidence?
  var after: ElementEvidence?
  var kind: Kind

  /// At least one of `before`/`after` must be non-nil (an element that
  /// existed in neither snapshot has nothing to represent) -- `id` comes
  /// from whichever is present, `before` taking priority when both are,
  /// so the same logical element keeps the same `id` across a resize/
  /// move where it's present on both sides.
  init(before: ElementEvidence?, after: ElementEvidence?, kind: Kind) {
    precondition(before != nil || after != nil, "LayoutChange needs at least one of before/after")
    self.id = before?.id ?? after!.id
    self.before = before
    self.after = after
    self.kind = kind
  }
}

enum PageLayoutDiff {
  /// How close two rect dimensions must be (in pixels) to count as
  /// "unchanged" -- real layouts have sub-pixel rounding noise from
  /// scroll/zoom/font-metrics that isn't a meaningful layout shift.
  static let defaultTolerance: Double = 0.5

  /// Matches `before` and `after` snapshots of the same page by locator
  /// (`ElementDiff.isLikelySameElement`'s candidate-overlap check) and
  /// classifies every element as unchanged/moved/resized/both/added/
  /// removed. An element present in both but whose only difference is
  /// content (text/image) is `.unchanged`, since only geometry is
  /// compared here -- that's the entire point of this being a distinct
  /// mode from `ElementDiff.diff`'s full property comparison.
  static func diff(before: [ElementEvidence], after: [ElementEvidence], tolerance: Double = defaultTolerance) -> [LayoutChange] {
    var remainingAfter = after
    var changes: [LayoutChange] = []

    for beforeElement in before {
      guard let matchIndex = remainingAfter.firstIndex(where: { ElementDiff.isLikelySameElement(beforeElement, $0) }) else {
        changes.append(LayoutChange(before: beforeElement, after: nil, kind: .removed))
        continue
      }
      let afterElement = remainingAfter.remove(at: matchIndex)
      changes.append(LayoutChange(before: beforeElement, after: afterElement, kind: classify(beforeElement.rect, afterElement.rect, tolerance: tolerance)))
    }

    for leftoverAfter in remainingAfter {
      changes.append(LayoutChange(before: nil, after: leftoverAfter, kind: .added))
    }

    return changes
  }

  private static func classify(_ before: Region, _ after: Region, tolerance: Double) -> LayoutChange.Kind {
    let dx = after.x - before.x
    let dy = after.y - before.y
    let dWidth = after.width - before.width
    let dHeight = after.height - before.height

    let moved = abs(dx) > tolerance || abs(dy) > tolerance
    let resized = abs(dWidth) > tolerance || abs(dHeight) > tolerance

    switch (moved, resized) {
    case (false, false): return .unchanged
    case (true, false): return .moved(dx: dx, dy: dy)
    case (false, true): return .resized(dWidth: dWidth, dHeight: dHeight)
    case (true, true): return .movedAndResized(dx: dx, dy: dy, dWidth: dWidth, dHeight: dHeight)
    }
  }
}
