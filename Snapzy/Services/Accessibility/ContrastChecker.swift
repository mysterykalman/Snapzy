//
//  ContrastChecker.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureCore module (owned by
//  the user; see docs/REFERENCE_PROVENANCE.md).
//

import Foundation

/// WCAG 2.x text/background contrast. Implements the actual WCAG 2.1
/// §1.4.3 formula, verified against its own textbook values (pure black
/// on pure white = 21:1) rather than approximated.
///
/// APCA (the newer, more perceptually-accurate contrast model) is
/// deliberately **not** implemented here — its real algorithm is
/// intricate and still evolving (APCA-W3 draft), and a subtly-wrong
/// reimplementation would be a correctness bug in a feature whose whole
/// point is correctness. This is a real, documented gap, not a silently
/// assumed-solved one.
enum ContrastChecker {
  struct RGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double
  }

  enum WCAGLevel: String, Equatable {
    case fail = "Fail"
    case aa = "AA"
    case aaa = "AAA"
  }

  /// WCAG relative luminance (0...1) of an sRGB color.
  static func relativeLuminance(_ color: RGB) -> Double {
    func linearize(_ component: Double) -> Double {
      let c = min(max(component, 0), 1)
      return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearize(color.red) + 0.7152 * linearize(color.green) + 0.0722 * linearize(color.blue)
  }

  /// The WCAG contrast ratio between two colors, always ≥ 1 regardless
  /// of which is passed as foreground/background.
  static func wcagContrastRatio(_ a: RGB, _ b: RGB) -> Double {
    let l1 = relativeLuminance(a)
    let l2 = relativeLuminance(b)
    let lighter = max(l1, l2)
    let darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
  }

  /// The pass/fail level for a given ratio, per WCAG 2.1 §1.4.3's
  /// thresholds (3:1 / 4.5:1 for large text, 4.5:1 / 7:1 for normal).
  static func wcagLevel(ratio: Double, isLargeText: Bool) -> WCAGLevel {
    if isLargeText {
      if ratio >= 4.5 { return .aaa }
      if ratio >= 3.0 { return .aa }
      return .fail
    } else {
      if ratio >= 7.0 { return .aaa }
      if ratio >= 4.5 { return .aa }
      return .fail
    }
  }

  /// Darkens or lightens `foreground` (whichever direction increases
  /// contrast against `background` — moving toward black vs. toward
  /// white) until `targetRatio` is met, via binary search on a uniform
  /// mix toward that extreme. This deliberately keeps the suggestion
  /// "nearby" (a shade of the same original color) rather than jumping
  /// to an arbitrary compliant color. If even the extreme (pure
  /// black/white) can't reach `targetRatio` against this particular
  /// background, returns that extreme — the best any adjustment of
  /// `foreground` alone can do.
  static func suggestCompliantForeground(foreground: RGB, background: RGB, targetRatio: Double) -> RGB {
    let towardBlackRatio = wcagContrastRatio(.init(red: 0, green: 0, blue: 0), background)
    let towardWhiteRatio = wcagContrastRatio(.init(red: 1, green: 1, blue: 1), background)
    let extreme: RGB = towardBlackRatio >= towardWhiteRatio ? .init(red: 0, green: 0, blue: 0) : .init(red: 1, green: 1, blue: 1)

    guard wcagContrastRatio(foreground, background) < targetRatio else { return foreground }
    guard wcagContrastRatio(extreme, background) >= targetRatio else { return extreme }

    func mix(_ t: Double) -> RGB {
      RGB(
        red: foreground.red + (extreme.red - foreground.red) * t,
        green: foreground.green + (extreme.green - foreground.green) * t,
        blue: foreground.blue + (extreme.blue - foreground.blue) * t
      )
    }

    var low = 0.0, high = 1.0
    for _ in 0..<40 {
      let mid = (low + high) / 2
      if wcagContrastRatio(mix(mid), background) >= targetRatio {
        high = mid
      } else {
        low = mid
      }
    }
    return mix(high)
  }
}
