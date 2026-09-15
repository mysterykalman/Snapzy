//
//  CommandPaletteWindowController.swift
//  Snapzy
//
//  Manages the Command Palette panel lifecycle -- a floating, non-
//  activating panel (ShortcutOverlayManager's established pattern),
//  since the palette is a quick modal-ish overlay rather than a
//  browse-the-data window.
//

import AppKit
import SwiftUI

@MainActor
final class CommandPaletteWindowController {
  static let shared = CommandPaletteWindowController()

  private var panel: NSPanel?
  private var deepLinkHandler: SnapzyDeepLinkHandler?

  private init() {}

  var isVisible: Bool { panel?.isVisible == true }

  func toggle(deepLinkHandler: SnapzyDeepLinkHandler) {
    if isVisible {
      hide()
    } else {
      show(deepLinkHandler: deepLinkHandler)
    }
  }

  func show(deepLinkHandler: SnapzyDeepLinkHandler) {
    self.deepLinkHandler = deepLinkHandler
    // Always rebuilt fresh (rather than reusing a hidden panel) so
    // reopening the palette starts with an empty query every time,
    // matching Spotlight/Alfred's own behavior.
    hide()

    let screen = ScreenUtility.activeScreen()
    let size = NSSize(width: 480, height: 360)
    let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2 + 80)

    let newPanel = CommandPalettePanel(
      contentRect: NSRect(origin: origin, size: size),
      styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    newPanel.isOpaque = false
    newPanel.backgroundColor = .clear
    newPanel.hasShadow = true
    newPanel.isFloatingPanel = true
    newPanel.hidesOnDeactivate = false
    newPanel.level = .floating
    newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    newPanel.isReleasedWhenClosed = false
    newPanel.contentView = NSHostingView(
      rootView: CommandPaletteView(
        onSelect: { [weak self] result in
          self?.hide()
          self?.deepLinkHandler?.perform(result.action)
        },
        onCancel: { [weak self] in
          self?.hide()
        }
      )
    )

    newPanel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    panel = newPanel
  }

  func hide() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
  }
}

/// A borderless, non-activating panel that can still become key, so
/// the search field and arrow-key navigation work without activating
/// the app -- matching `PixelMeterOverlay`'s identical `MeterPanel`
/// pattern for the same style-mask combination.
private final class CommandPalettePanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
