//
//  ElementEvidence.swift
//  Snapzy
//
//  Ported from the original Capture app's CaptureInspection module
//  (owned by the user; see docs/REFERENCE_PROVENANCE.md).
//
//  The central browser-inspection data object. Populated by the Chromium
//  extension's inspector content scripts and delivered to the Mac app
//  over the BrowserBridge Native Messaging -> Unix-socket bridge; this
//  file defines the data model that the visual-diff subsystem
//  (PageLayoutDiff, ElementDiff, MultiElementComparison) operates on.
//

import Foundation

struct ElementEvidence: Codable, Equatable, Identifiable {
  struct Viewport: Codable, Equatable {
    var width: Double
    var height: Double
    var devicePixelRatio: Double
    var scrollX: Double
    var scrollY: Double

    init(width: Double, height: Double, devicePixelRatio: Double, scrollX: Double, scrollY: Double) {
      self.width = width
      self.height = height
      self.devicePixelRatio = devicePixelRatio
      self.scrollX = scrollX
      self.scrollY = scrollY
    }
  }

  var id: UUID
  var capturedAt: Date
  var url: String
  var title: String
  var viewport: Viewport
  var locator: ElementLocator
  var rect: Region
  /// A standard absolute XPath (the same convention browser DevTools'
  /// own "Copy XPath" produces), purely for display/copy; `locator`'s
  /// own candidates remain the re-identification mechanism, not this.
  var xpath: String?

  /// Deliberately loosely-typed JSON blobs for the deeper forensic
  /// categories (box model, typography, appearance, layout,
  /// accessibility, CSS variables) -- these vary enormously by element
  /// and are consumed by UI that renders whatever keys are present
  /// rather than a fixed Swift struct per category. Stored as raw JSON
  /// text so this type doesn't need to track the extension's evolving
  /// field set 1:1.
  var boxModelJSON: String?
  var typographyJSON: String?
  var appearanceJSON: String?
  var layoutJSON: String?
  var accessibilityJSON: String?
  var cssVariablesJSON: String?

  init(
    id: UUID = UUID(),
    capturedAt: Date = Date(),
    url: String,
    title: String,
    viewport: Viewport,
    locator: ElementLocator,
    rect: Region,
    xpath: String? = nil,
    boxModelJSON: String? = nil,
    typographyJSON: String? = nil,
    appearanceJSON: String? = nil,
    layoutJSON: String? = nil,
    accessibilityJSON: String? = nil,
    cssVariablesJSON: String? = nil
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.url = url
    self.title = title
    self.viewport = viewport
    self.locator = locator
    self.rect = rect
    self.xpath = xpath
    self.boxModelJSON = boxModelJSON
    self.typographyJSON = typographyJSON
    self.appearanceJSON = appearanceJSON
    self.layoutJSON = layoutJSON
    self.accessibilityJSON = accessibilityJSON
    self.cssVariablesJSON = cssVariablesJSON
  }
}
