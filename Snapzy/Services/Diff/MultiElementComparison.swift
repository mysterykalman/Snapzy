//
//  MultiElementComparison.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureDiff module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//
//  "Multi-select inspection: compare dimensions/typography/colours/
//  radius/spacing/CSS variables across selection (e.g. 'Selected: 12 PLP
//  cards / 11 use radius 8px / 1 uses radius 6px')." Given N
//  `ElementEvidence` captures of a *set* of elements (not necessarily the
//  same logical element across time, unlike `ElementDiff` -- this is "how
//  consistent is this group right now"), clusters each property's values
//  by frequency, exactly matching that worked example's phrasing.
//

import Foundation

struct PropertyDistribution: Equatable {
  var category: String
  var property: String
  /// (value, count) pairs, most-common first. A property with only one
  /// distinct value across the whole selection means every element
  /// agrees -- the implicit "is this consistent?" question, answerable
  /// as `valueCounts.count == 1`.
  var valueCounts: [(value: String, count: Int)]

  static func == (lhs: PropertyDistribution, rhs: PropertyDistribution) -> Bool {
    lhs.category == rhs.category && lhs.property == rhs.property &&
      lhs.valueCounts.elementsEqual(rhs.valueCounts, by: { $0.value == $1.value && $0.count == $1.count })
  }
}

enum MultiElementComparison {
  /// Compares `evidences` (2 or more) property by property -- `rect`'s
  /// width/height (the "dimensions") plus every key found across any
  /// evidence's typography/appearance/box-model JSON -- returning one
  /// `PropertyDistribution` per property, sorted so the *least*
  /// consistent properties (most distinct values) come first, since
  /// those are the ones actually worth a human's attention (the worked
  /// example leads with the outlier, "1 uses radius 6px," not the
  /// property everyone already agrees on).
  static func compare(_ evidences: [ElementEvidence]) -> [PropertyDistribution] {
    guard evidences.count >= 2 else { return [] }

    var perPropertyValues: [(category: String, property: String)] = []
    var seen: Set<String> = []
    func registerProperty(_ category: String, _ property: String) {
      let key = "\(category).\(property)"
      guard !seen.contains(key) else { return }
      seen.insert(key)
      perPropertyValues.append((category, property))
    }

    registerProperty("rect", "width")
    registerProperty("rect", "height")
    for evidence in evidences {
      for key in ElementDiff.parseFlatJSONObject(evidence.typographyJSON).keys { registerProperty("typography", key) }
      for key in ElementDiff.parseFlatJSONObject(evidence.appearanceJSON).keys { registerProperty("appearance", key) }
      for key in ElementDiff.parseFlatJSONObject(evidence.boxModelJSON).keys { registerProperty("boxModel", key) }
    }

    var distributions: [PropertyDistribution] = []
    for (category, property) in perPropertyValues {
      var counts: [String: Int] = [:]
      for evidence in evidences {
        let value = stringValue(for: category, property: property, in: evidence)
        counts[value, default: 0] += 1
      }
      let sortedCounts = counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
      distributions.append(PropertyDistribution(category: category, property: property, valueCounts: sortedCounts.map { ($0.key, $0.value) }))
    }

    // Most distinct values (least consistent) first; ties broken by
    // category/property name for a stable, reproducible order.
    return distributions.sorted { lhs, rhs in
      if lhs.valueCounts.count != rhs.valueCounts.count { return lhs.valueCounts.count > rhs.valueCounts.count }
      if lhs.category != rhs.category { return lhs.category < rhs.category }
      return lhs.property < rhs.property
    }
  }

  private static func stringValue(for category: String, property: String, in evidence: ElementEvidence) -> String {
    if category == "rect" {
      let value = property == "width" ? evidence.rect.width : evidence.rect.height
      return value == value.rounded() ? String(Int(value)) : String(value)
    }
    let json: String?
    switch category {
    case "typography": json = evidence.typographyJSON
    case "appearance": json = evidence.appearanceJSON
    case "boxModel": json = evidence.boxModelJSON
    default: json = nil
    }
    return ElementDiff.parseFlatJSONObject(json)[property] ?? ""
  }
}
