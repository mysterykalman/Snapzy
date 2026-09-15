//
//  ElementDiff.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureDiff module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//
//  Same-element ("element" diff mode) and style-property diffing: two
//  ElementEvidence captures of what should be the same logical element
//  (matched by locator, e.g. before/after a deploy, or across
//  breakpoints/browsers), diffed property by property. Also directly
//  supports cross-breakpoint element comparison -- the two evidences
//  being compared don't have to come from the same viewport.
//
//  `PageLayoutDiff` reuses `isLikelySameElement` to match up before/after
//  snapshots by locator rather than duplicating that matching logic.
//

import Foundation

struct PropertyDifference: Equatable {
  var category: String
  var property: String
  var before: String
  var after: String
}

enum ElementDiff {
  /// True if `before` and `after` are plausibly "the same element" --
  /// their locators share at least one candidate strategy+value pair in
  /// common. Diffing two evidences that aren't the same element would
  /// produce meaningless property differences, so callers should check
  /// this (or already know it from having captured both via the same
  /// locator) before trusting a diff result.
  static func isLikelySameElement(_ before: ElementEvidence, _ after: ElementEvidence) -> Bool {
    let beforeCandidates = Set(before.locator.candidates.map { "\($0.strategy.rawValue):\($0.value)" })
    let afterCandidates = Set(after.locator.candidates.map { "\($0.strategy.rawValue):\($0.value)" })
    return !beforeCandidates.isDisjoint(with: afterCandidates)
  }

  /// Diffs `rect` (position/size) plus every key found in the
  /// loosely-typed JSON forensic categories (typography/appearance/box
  /// model). A key present in only one side is reported too (before or
  /// after is `""`), since "a property appeared/disappeared" is itself
  /// a meaningful diff (e.g. a CSS variable that stopped being used).
  static func diff(_ before: ElementEvidence, _ after: ElementEvidence) -> [PropertyDifference] {
    var differences: [PropertyDifference] = []

    differences.append(contentsOf: diffRect(before.rect, after.rect))
    differences.append(contentsOf: diffJSONCategory("typography", before.typographyJSON, after.typographyJSON))
    differences.append(contentsOf: diffJSONCategory("appearance", before.appearanceJSON, after.appearanceJSON))
    differences.append(contentsOf: diffJSONCategory("boxModel", before.boxModelJSON, after.boxModelJSON))

    return differences
  }

  private static func diffRect(_ before: Region, _ after: Region) -> [PropertyDifference] {
    var result: [PropertyDifference] = []
    func compare(_ property: String, _ beforeValue: Double, _ afterValue: Double) {
      guard beforeValue != afterValue else { return }
      result.append(PropertyDifference(category: "rect", property: property, before: format(beforeValue), after: format(afterValue)))
    }
    compare("x", before.x, after.x)
    compare("y", before.y, after.y)
    compare("width", before.width, after.width)
    compare("height", before.height, after.height)
    return result
  }

  private static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
  }

  private static func diffJSONCategory(_ category: String, _ before: String?, _ after: String?) -> [PropertyDifference] {
    let beforeDict = parseFlatJSONObject(before)
    let afterDict = parseFlatJSONObject(after)
    let allKeys = Set(beforeDict.keys).union(afterDict.keys)

    return allKeys.compactMap { key in
      let beforeValue = beforeDict[key] ?? ""
      let afterValue = afterDict[key] ?? ""
      guard beforeValue != afterValue else { return nil }
      return PropertyDifference(category: category, property: key, before: beforeValue, after: afterValue)
    }.sorted { $0.property < $1.property }
  }

  /// Parses a JSON object string into `[String: String]`, stringifying
  /// every value (numbers/bools/strings alike) so e.g. `fontSize: 14`
  /// and `fontSize: "14"` compare consistently regardless of how a
  /// given content-script field happened to be typed. Not recursive --
  /// evidence's forensic JSON categories are flat, and a malformed/
  /// non-object payload safely yields an empty dictionary rather than
  /// throwing. `internal` (not `private`) so `MultiElementComparison`
  /// can reuse this exact parsing instead of duplicating it.
  static func parseFlatJSONObject(_ json: String?) -> [String: String] {
    guard let json, let data = json.data(using: .utf8) else { return [:] }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    var result: [String: String] = [:]
    for (key, value) in object {
      switch value {
      case let string as String: result[key] = string
      case let number as NSNumber: result[key] = number.stringValue
      case is NSNull: result[key] = "null"
      default: result[key] = "\(value)"
      }
    }
    return result
  }
}
