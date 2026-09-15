//
//  FigmaOverlayManager.swift
//  Snapzy
//
//  A native reimplementation of the "Figma overlay" workflow studied
//  from the read-only figma-overlay reference (MIT (c) Pitu; see
//  docs/REFERENCE_PROVENANCE.md) -- that reference is a Vue web
//  component (a browser-page overlay), so its code can't be ported
//  directly into a native macOS app; the UX it demonstrates is what's
//  reused here, rebuilt as a floating AppKit panel following this
//  project's own PixelMeterOverlay/ShortcutOverlayManager conventions.
//
//  Workflow: copy a design as an image from Figma ("Copy as SVG" or
//  "Copy as PNG"), then summon this overlay. It loads whatever image is
//  on the general pasteboard, floats it semi-transparently above every
//  other window, and lets the user drag it around (mouse) or nudge it
//  pixel-by-pixel (arrow keys) to line it up against the live
//  implementation underneath -- while a small control panel offers an
//  opacity slider and a click-through toggle, same as the reference.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class FigmaOverlayManager: ObservableObject {
  static let shared = FigmaOverlayManager()

  enum LoadError: LocalizedError {
    case unsupportedContent

    var errorDescription: String? {
      switch self {
      case .unsupportedContent:
        return "No image found on the clipboard. Copy a design as SVG or PNG (e.g. Figma's \"Copy as SVG\") and try again."
      }
    }
  }

  @Published var opacity: Double = 0.5 {
    didSet { overlayWindow?.alphaValue = opacity }
  }
  @Published var ignoresClicks: Bool = false {
    didSet { overlayWindow?.ignoresMouseEvents = ignoresClicks }
  }

  private var overlayWindow: FigmaOverlayPanel?
  private var controlPanel: NSPanel?

  private init() {}

  // Every class implicitly picks up this project's
  // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor build setting; without an
  // explicit deinit the compiler synthesizes an isolated one that hits
  // a Swift runtime bug on deallocation of a non-singleton instance
  // (see DatabaseManager.swift / BrowserBridgeCoordinator.swift for the
  // fully root-caused writeup). This type is only ever used via
  // `.shared`, but the fix is free insurance against a future transient
  // instance (e.g. in a test) hitting the same bug.
  nonisolated deinit {}

  var isVisible: Bool { overlayWindow?.isVisible == true }

  func toggle() {
    if isVisible {
      hide()
    } else {
      do {
        try show()
      } catch {
        DiagnosticLogger.shared.log(
          .warning,
          .action,
          "Could not present Figma overlay",
          context: ["error": error.localizedDescription]
        )
      }
    }
  }

  @discardableResult
  func show() throws -> Bool {
    guard let image = Self.loadImageFromPasteboard() else {
      throw LoadError.unsupportedContent
    }

    hide()

    let screen = ScreenUtility.activeScreen()
    let imageSize = image.size.width > 0 && image.size.height > 0 ? image.size : CGSize(width: 400, height: 300)
    let origin = CGPoint(
      x: screen.frame.midX - imageSize.width / 2,
      y: screen.frame.midY - imageSize.height / 2
    )

    let panel = FigmaOverlayPanel(contentRect: CGRect(origin: origin, size: imageSize))
    let contentView = FigmaOverlayContentView(frame: NSRect(origin: .zero, size: imageSize))
    contentView.image = image
    contentView.manager = self
    panel.contentView = contentView
    panel.alphaValue = opacity
    panel.ignoresMouseEvents = ignoresClicks
    panel.orderFrontRegardless()
    panel.makeKey()
    overlayWindow = panel

    presentControlPanel(near: screen)

    DiagnosticLogger.shared.log(.info, .action, "Presented Figma overlay", context: ["width": "\(imageSize.width)", "height": "\(imageSize.height)"])
    return true
  }

  func hide() {
    overlayWindow?.orderOut(nil)
    overlayWindow?.close()
    overlayWindow = nil

    controlPanel?.orderOut(nil)
    controlPanel?.close()
    controlPanel = nil
  }

  fileprivate func nudge(dx: CGFloat, dy: CGFloat) {
    guard let overlayWindow else { return }
    var frame = overlayWindow.frame
    frame.origin.x += dx
    frame.origin.y += dy
    overlayWindow.setFrameOrigin(frame.origin)
  }

  private func presentControlPanel(near screen: NSScreen) {
    let panel = NSPanel(
      contentRect: CGRect(x: screen.frame.minX + 16, y: screen.frame.minY + 16, width: 260, height: 130),
      styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.title = "Design Overlay"
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.contentView = NSHostingView(rootView: FigmaOverlayControlView(manager: self))
    panel.orderFrontRegardless()
    controlPanel = panel
  }

  private static func loadImageFromPasteboard() -> NSImage? {
    let pasteboard = NSPasteboard.general

    if let string = pasteboard.string(forType: .string) {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("<svg"), let data = trimmed.data(using: .utf8), let image = NSImage(data: data), image.isValid {
        return image
      }
    }

    if let image = NSImage(pasteboard: pasteboard), image.isValid {
      return image
    }

    return nil
  }
}

// MARK: - Overlay window

/// A borderless, non-activating panel that can still become key, so
/// arrow-key nudging and Escape-to-remove work without activating the
/// app (which would switch away from a full-screen Space).
private final class FigmaOverlayPanel: NSPanel {
  init(contentRect: CGRect) {
    super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isFloatingPanel = true
    hidesOnDeactivate = false
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    isReleasedWhenClosed = false
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

// MARK: - Overlay content view

/// Draws the loaded design image and drives dragging (mouse) and
/// nudging (arrow keys), mirroring the reference's own interaction
/// model (drag to reposition, arrow keys for pixel-precise alignment,
/// Escape to remove).
private final class FigmaOverlayContentView: NSView {
  weak var manager: FigmaOverlayManager?
  var image: NSImage?

  private var dragOffsetInWindow: CGPoint?

  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
  }

  override func draw(_ dirtyRect: NSRect) {
    image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
  }

  override func mouseDown(with event: NSEvent) {
    dragOffsetInWindow = event.locationInWindow
  }

  override func mouseDragged(with event: NSEvent) {
    guard let window, let dragOffsetInWindow else { return }
    let screenPoint = NSEvent.mouseLocation
    let newOrigin = CGPoint(x: screenPoint.x - dragOffsetInWindow.x, y: screenPoint.y - dragOffsetInWindow.y)
    window.setFrameOrigin(newOrigin)
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 126: manager?.nudge(dx: 0, dy: 1)  // Up
    case 125: manager?.nudge(dx: 0, dy: -1)  // Down
    case 123: manager?.nudge(dx: -1, dy: 0)  // Left
    case 124: manager?.nudge(dx: 1, dy: 0)  // Right
    case 53: manager?.hide()  // Escape
    default: super.keyDown(with: event)
    }
  }

  override func cancelOperation(_ sender: Any?) {
    manager?.hide()
  }
}

// MARK: - Control panel

private struct FigmaOverlayControlView: View {
  @ObservedObject var manager: FigmaOverlayManager

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Slider(value: $manager.opacity, in: 0...1) {
        Text("Opacity")
      }
      Toggle("Ignore clicks", isOn: $manager.ignoresClicks)
      Text("\u{2190}\u{2191}\u{2192}\u{2193} to move \u{00B7} Esc to remove")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Remove Overlay") {
        manager.hide()
      }
    }
    .padding(16)
  }
}
