//
//  CaptureTrayWindowController.swift
//  Snapzy
//
//  Manages the Capture Tray window lifecycle -- a standard titled
//  window (browse-the-data surface, same category as History's own
//  window), following InspectionResultsWindowController's exact
//  pattern.
//

import AppKit
import SwiftUI

@MainActor
final class CaptureTrayWindowController {
  static let shared = CaptureTrayWindowController()

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
    let size = NSSize(width: 460, height: 380)
    let origin = NSPoint(x: (screen.frame.width - size.width) / 2, y: (screen.frame.height - size.height) / 2)

    let newWindow = NSWindow(
      contentRect: NSRect(origin: origin, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    newWindow.title = "Capture Tray"
    newWindow.isReleasedWhenClosed = false
    newWindow.contentView = NSHostingView(
      rootView: CaptureTrayView(store: CaptureTrayStore.shared, onAssemble: Self.assemble)
    )
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

  /// Hands the tray's ordered file list to Annotate's existing Combine
  /// Images flow (needs 2+ images, matching `canAssemble`), then clears
  /// the tray since its contents have been handed off to an editable
  /// canvas -- mirroring how a physical tray empties once its contents
  /// are placed on the work surface.
  private static func assemble(urls: [URL]) {
    guard urls.count >= 2 else { return }
    AnnotateManager.shared.openCombineImages(urls: urls)
    CaptureTrayStore.shared.clear()
    CaptureTrayWindowController.shared.window?.close()
  }
}
