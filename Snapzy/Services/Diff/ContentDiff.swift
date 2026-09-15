//
//  ContentDiff.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureDiff module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//
//  "Content" diff mode (visible text/image differences) -- the
//  complement to `PageLayoutDiff` (which deliberately *ignores* content
//  and only reports geometry) and `ElementDiff` (which diffs every
//  style/rect property of one already-matched element). This mode
//  answers a narrower, different question: across a whole page, which
//  DOM-anchored elements' own *visible content* changed, regardless of
//  whether they also moved or resized. Operates on a caller-supplied
//  snapshot pair ([selector: visibleText] -- the shape a browser bridge
//  would report by walking the DOM and reading each element's own text/
//  alt-text content) since this environment has no live browser session
//  to capture that walk itself; the comparison logic is what's genuinely
//  pure and testable here.
//

import Foundation

struct ContentChange: Equatable {
  enum Kind: Equatable {
    case added
    case removed
    case changed
  }

  var selector: String
  var kind: Kind
  var before: String?
  var after: String?

  init(selector: String, kind: Kind, before: String?, after: String?) {
    self.selector = selector
    self.kind = kind
    self.before = before
    self.after = after
  }
}

enum ContentDiff {
  /// `before`/`after` are `[selector: visibleText]` snapshots of the
  /// same page (or the same page across two captures). A selector
  /// present in only one snapshot is reported `.added`/`.removed`
  /// (presence and value both matter, not just value); a selector in
  /// both with different text is `.changed`; identical text -- even if
  /// the *element* itself moved (a `PageLayoutDiff` concern, not this
  /// one) -- is not reported at all. Results are sorted by selector for
  /// a stable, deterministic order regardless of the caller's
  /// dictionary iteration order.
  static func diff(before: [String: String], after: [String: String]) -> [ContentChange] {
    let allSelectors = Set(before.keys).union(after.keys)
    return allSelectors.sorted().compactMap { selector in
      let beforeText = before[selector]
      let afterText = after[selector]
      switch (beforeText, afterText) {
      case (nil, let after?):
        return ContentChange(selector: selector, kind: .added, before: nil, after: after)
      case (let before?, nil):
        return ContentChange(selector: selector, kind: .removed, before: before, after: nil)
      case (let before?, let after?) where before != after:
        return ContentChange(selector: selector, kind: .changed, before: before, after: after)
      default:
        return nil
      }
    }
  }
}
