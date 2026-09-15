//
//  CaptureComparisonWindowController.swift
//  Snapzy
//
//  Manages the Compare Captures window lifecycle -- a standard titled
//  window (browse/inspect surface, not a floating HUD panel), following
//  InspectionResultsWindowController's exact pattern. Unlike that
//  singleton window, comparisons are opened per-pair, so this manager
//  tracks a set of open windows rather than a single shared one.
//

import AppKit
import SwiftUI

@MainActor
final class CaptureComparisonWindowController {
  static let shared = CaptureComparisonWindowController()

  private var openWindows: [NSWindow] = []

  private init() {}

  func showComparison(before: CGImage, beforeLabel: String, after: CGImage, afterLabel: String) {
    let screen = ScreenUtility.activeScreen()
    let size = NSSize(width: 900, height: 640)
    let origin = NSPoint(x: (screen.frame.width - size.width) / 2, y: (screen.frame.height - size.height) / 2)

    let window = NSWindow(
      contentRect: NSRect(origin: origin, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Compare Captures"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: CaptureComparisonView(before: before, beforeLabel: beforeLabel, after: after, afterLabel: afterLabel)
    )
    window.center()

    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self, weak window] _ in
      guard let self, let window else { return }
      openWindows.removeAll { $0 === window }
    }

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    openWindows.append(window)
  }
}
