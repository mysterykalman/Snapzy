//
//  CommandPaletteAction.swift
//  Snapzy
//
//  The searchable command list the Command Palette (spec §2.27: "all
//  less-common commands -- do not put every possible tool in the
//  permanent toolbar") offers. Each entry wraps an existing
//  `SnapzyDeepLinkAction` so the palette reuses exactly the same
//  dispatch path `snapzy://` URLs already use
//  (`SnapzyDeepLinkHandler.perform(_:)`) rather than a second command-
//  execution mechanism.
//

import Foundation

struct CommandPaletteAction: Identifiable {
  let id: String
  let title: String
  let systemImage: String
  let action: SnapzyDeepLinkAction

  /// The full catalog, in a sensible default (most-common-first) order.
  /// Search filters this list rather than reordering it, so an empty
  /// query shows commands in this same order every time.
  static let all: [CommandPaletteAction] = [
    CommandPaletteAction(id: "captureArea", title: "Capture Area", systemImage: "viewfinder", action: .captureArea),
    CommandPaletteAction(id: "captureFullscreen", title: "Capture Full Screen", systemImage: "macwindow", action: .captureFullscreen),
    CommandPaletteAction(id: "captureActiveWindow", title: "Capture Active Window", systemImage: "macwindow.badge.plus", action: .captureActiveWindow),
    CommandPaletteAction(id: "captureRepeatArea", title: "Capture Repeat Area", systemImage: "arrow.trianglehead.2.clockwise", action: .captureRepeatArea),
    CommandPaletteAction(id: "captureAreaAnnotate", title: "Capture Area & Annotate", systemImage: "pencil.and.outline", action: .captureAreaAnnotate),
    CommandPaletteAction(id: "captureScrolling", title: "Capture Scrolling", systemImage: "arrow.up.and.down", action: .captureScrolling),
    CommandPaletteAction(id: "captureOCR", title: "Capture Text (OCR)", systemImage: "text.viewfinder", action: .captureOCR),
    CommandPaletteAction(id: "captureSmartElement", title: "Capture Smart Element", systemImage: "square.dashed.inset.filled", action: .captureSmartElement),
    CommandPaletteAction(id: "captureObjectCutout", title: "Capture Object Cutout", systemImage: "scissors", action: .captureObjectCutout),
    CommandPaletteAction(id: "delayedCapture", title: "Delayed Capture", systemImage: "timer", action: .delayedCapture(seconds: nil)),
    CommandPaletteAction(id: "recordScreen", title: "Start Screen Recording", systemImage: "record.circle", action: .recordScreen),
    CommandPaletteAction(id: "recordApplication", title: "Start Application Recording", systemImage: "record.circle.fill", action: .recordApplication),
    CommandPaletteAction(id: "openAnnotate", title: "Open Annotate", systemImage: "pencil.tip.crop.circle", action: .openAnnotate),
    CommandPaletteAction(id: "openCombine", title: "Combine Images\u{2026}", systemImage: "square.on.square", action: .openCombine([])),
    CommandPaletteAction(id: "openVideoEditor", title: "Open Video Editor", systemImage: "film", action: .openVideoEditor),
    CommandPaletteAction(id: "openHistory", title: "Open History", systemImage: "clock.arrow.circlepath", action: .openHistory),
    CommandPaletteAction(id: "openCaptureTray", title: "Open Capture Tray", systemImage: "tray.full", action: .openCaptureTray),
    CommandPaletteAction(id: "openCloudUploads", title: "Open Cloud Uploads", systemImage: "icloud", action: .openCloudUploads),
    CommandPaletteAction(id: "openInspectionResults", title: "Open Inspection Results", systemImage: "list.bullet.clipboard", action: .openInspectionResults),
    CommandPaletteAction(id: "colorLoupe", title: "Color Picker", systemImage: "eyedropper", action: .colorLoupe),
    CommandPaletteAction(id: "ruler", title: "Pixel Ruler", systemImage: "ruler", action: .ruler),
    CommandPaletteAction(id: "designOverlay", title: "Toggle Design Overlay", systemImage: "square.stack.3d.up", action: .designOverlay),
    CommandPaletteAction(id: "showShortcuts", title: "Show Keyboard Shortcuts", systemImage: "keyboard", action: .showShortcuts),
    CommandPaletteAction(id: "openSettings", title: "Open Settings", systemImage: "gearshape", action: .openSettings(nil)),
  ]

  /// Case-insensitive substring match against the title -- simple and
  /// predictable rather than a fuzzy-match scoring scheme, matching
  /// this app's other search surfaces (e.g. History's own filename
  /// search).
  static func matching(_ query: String) -> [CommandPaletteAction] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return all }
    return all.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
  }
}
