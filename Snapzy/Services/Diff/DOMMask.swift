//
//  DOMMask.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureDiff module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//
//  Noise suppression: mask selected regions so a diff ignores known
//  dynamic content (e.g. "Ignore `.review-count`"). DOM masks keyed by
//  CSS selector are preferred over fixed pixel masks because they
//  remain stable across geometry changes. `ImageDiff.pixelDiff`'s
//  `ignoredRegions` already implements the *fixed*-pixel-mask half of
//  that noise suppression; this is the DOM-mask half -- a mask keyed by
//  selector rather than a baked-in rectangle, resolved to a real
//  rectangle at diff time (the resolution itself needs a live browser
//  session reporting the selector's *current* `getBoundingClientRect()`,
//  which this environment doesn't have -- same category of limitation
//  as every other browser-bridge-dependent feature in this project).
//  What's genuinely pure and testable here is the resolution/bookkeeping
//  logic: turning a selector->rect lookup into the `[CGRect]`
//  `ImageDiff` already accepts, and reporting which selectors matched
//  nothing this time -- mirroring the "Anchor not found" convention (if
//  the element is gone, show "Anchor not found" rather than placing the
//  arrow at stale coordinates) rather than silently dropping a mask
//  that no longer matches anything.
//

import CoreGraphics

struct DOMMask: Codable, Equatable {
  var selector: String
  var label: String?

  init(selector: String, label: String? = nil) {
    self.selector = selector
    self.label = label
  }
}

struct DOMMaskResolution: Equatable {
  /// Real rectangles ready to pass straight into
  /// `ImageDiff.pixelDiff(ignoredRegions:)`.
  var regions: [CGRect]
  /// Masks whose selector matched nothing in the live page this time --
  /// surfaced explicitly rather than silently ignored, so a stale/typo'd
  /// selector doesn't quietly stop suppressing noise without anyone
  /// noticing.
  var unresolvedSelectors: [String]

  init(regions: [CGRect], unresolvedSelectors: [String]) {
    self.regions = regions
    self.unresolvedSelectors = unresolvedSelectors
  }
}

enum DOMMaskResolver {
  /// `liveRects` is keyed by selector -- exactly the shape a browser
  /// bridge would report back for a set of requested selectors (one
  /// `getBoundingClientRect()` per selector that still matches an
  /// element on the live page; a selector matching nothing is simply
  /// absent from the dictionary, not present with a zero rect).
  static func resolve(_ masks: [DOMMask], liveRects: [String: CGRect]) -> DOMMaskResolution {
    var regions: [CGRect] = []
    var unresolved: [String] = []
    for mask in masks {
      if let rect = liveRects[mask.selector] {
        regions.append(rect)
      } else {
        unresolved.append(mask.selector)
      }
    }
    return DOMMaskResolution(regions: regions, unresolvedSelectors: unresolved)
  }
}
