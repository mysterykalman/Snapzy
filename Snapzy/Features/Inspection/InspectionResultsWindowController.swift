//
//  InspectionResultsWindowController.swift
//  Snapzy
//
//  Manages the Inspection Results window lifecycle -- a standard,
//  titled window (not a floating HUD panel) since this is a browse-
//  the-data surface, same category as History's own main window.
//

import AppKit
import SwiftUI

@MainActor
final class InspectionResultsWindowController {
  static let shared = InspectionResultsWindowController()

  private var window: NSWindow?

  private init() {}

  var isVisible: Bool { window?.isVisible == true }

  @discardableResult
  func toggleWindow() -> Bool {
    if isVisible {
      window?.close()
      return false
    }
    showWindow()
    return true
  }

  func showWindow() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let screen = NSScreen.main ?? NSScreen.screens.first!
    let size = NSSize(width: 560, height: 420)
    let origin = NSPoint(x: (screen.frame.width - size.width) / 2, y: (screen.frame.height - size.height) / 2)

    let newWindow = NSWindow(
      contentRect: NSRect(origin: origin, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    newWindow.title = "Inspection Results"
    newWindow.isReleasedWhenClosed = false
    newWindow.contentView = NSHostingView(rootView: InspectionResultsView(store: InspectionFindingsStore.shared))
    newWindow.center()

    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: newWindow, queue: .main
    ) { [weak self] _ in
      self?.window = nil
    }

    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window = newWindow
  }
}
