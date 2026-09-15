//
//  WindowShadowPreference.swift
//  Snapzy
//
//  Resolves the "Include window shadow in Application Capture" preference
//  (PreferencesKeys.captureIncludeWindowShadow) to the value
//  SCStreamConfiguration.ignoreShadowsSingleWindow expects.
//

import AppKit
import Foundation

/// Resolves the "Include window shadow in Application Capture" preference
/// (PreferencesKeys.captureIncludeWindowShadow, default `defaultIncludeShadow`)
/// to the value `SCStreamConfiguration.ignoreShadowsSingleWindow` expects.
///
/// The API field is INVERTED relative to the user-facing toggle:
/// - shadow included  -> `ignoreShadowsSingleWindow == false`
/// - shadow excluded  -> `ignoreShadowsSingleWindow == true`
///
/// This is the single source of truth for that inversion so a future contributor
/// cannot silently flip the sign at the five capture-configuration call sites.
enum WindowShadowPreference {
  /// Default for the stored preference. `true` preserves legacy single-window
  /// capture output (shadow on) exactly until the user opts out.
  static let defaultIncludeShadow: Bool = true

  /// Maps the stored "include shadow" flag to the `SCStreamConfiguration` value.
  static func ignoreShadowsSingleWindow(includeShadow: Bool) -> Bool { !includeShadow }

  /// Resolves whether *this* single-window capture should include its
  /// shadow: the stored preference, unless Option is held at the moment
  /// the capture's `SCStreamConfiguration` is built -- the spec's
  /// "Option-click (or configurable modifier) captures window without
  /// its normal shadow" requirement. For a single-window screenshot this
  /// runs essentially synchronously right after the click that started
  /// it, so checking the live modifier state here (rather than
  /// threading a captured-at-click-time flag through several capture-
  /// pipeline layers) reflects the same held-down-during-the-gesture
  /// intent without widening every window-capture call site's
  /// signature. When Option is *not* held, this falls through to
  /// `storedIncludeShadow` exactly as before.
  static func resolvedIncludeShadow(storedIncludeShadow: Bool) -> Bool {
    NSEvent.modifierFlags.contains(.option) ? false : storedIncludeShadow
  }
}
