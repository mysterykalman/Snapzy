//
//  DelayedCaptureCountdownOverlay.swift
//  Snapzy
//
//  Timed Capture (spec: "preset delays, arbitrary numeric delay,
//  countdown overlay") -- a real gap the product-completeness audit
//  (docs/GAP_AUDIT.md) found: no delay-before-capture existed anywhere
//  in the app. Shows a full-screen numeric countdown, then calls a
//  completion handler so the caller can invoke whichever real capture
//  mode it likes (area/window/fullscreen) once the countdown reaches
//  zero -- this overlay only owns the "wait and show a countdown"
//  concern, not capture itself, so it composes with every existing
//  capture entry point rather than duplicating any of them.
//
//  Follows PixelMeterOverlay's established floating-panel pattern
//  (non-activating panel across every screen, static strong reference
//  kept alive for the duration of the interaction, Esc cancels).
//

import AppKit

@MainActor
final class DelayedCaptureCountdownOverlay {
  private static var active: DelayedCaptureCountdownOverlay?

  private var windows: [NSWindow] = []
  private var remainingSeconds: Int
  private var timer: Timer?
  private var completion: ((Bool) -> Void)?
  private var didFinish = false

  private init(seconds: Int) {
    self.remainingSeconds = seconds
  }

  /// Shows a full-screen countdown for `seconds`, then invokes
  /// `completion(true)`. Pressing Escape cancels early with
  /// `completion(false)`. `seconds <= 0` invokes `completion(true)`
  /// immediately with no overlay at all.
  static func present(seconds: Int, completion: @escaping (Bool) -> Void) {
    guard seconds > 0 else {
      completion(true)
      return
    }

    active?.finish(success: false)

    let overlay = DelayedCaptureCountdownOverlay(seconds: seconds)
    overlay.completion = completion
    active = overlay
    overlay.show()
  }

  private func show() {
    let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens

    for screen in screens {
      let window = NSPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = false
      window.ignoresMouseEvents = true
      window.isFloatingPanel = true
      window.hidesOnDeactivate = false
      window.level = .screenSaver
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      window.setFrame(screen.frame, display: false)

      let view = CountdownView(frame: NSRect(origin: .zero, size: screen.frame.size))
      view.remainingSeconds = remainingSeconds
      window.contentView = view

      windows.append(window)
      window.orderFrontRegardless()
    }

    startTimer()
    setUpEscapeMonitor()
  }

  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.tick()
      }
    }
  }

  private func tick() {
    remainingSeconds -= 1
    if remainingSeconds <= 0 {
      finish(success: true)
      return
    }
    for case let view as CountdownView in windows.compactMap(\.contentView) {
      view.remainingSeconds = remainingSeconds
      view.needsDisplay = true
    }
  }

  private var escapeMonitor: Any?

  private func setUpEscapeMonitor() {
    escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return }  // Escape
      Task { @MainActor in
        self?.finish(success: false)
      }
    }
  }

  private func finish(success: Bool) {
    guard !didFinish else { return }
    didFinish = true

    timer?.invalidate()
    timer = nil
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
      self.escapeMonitor = nil
    }
    for window in windows {
      window.orderOut(nil)
    }
    windows.removeAll()

    if DelayedCaptureCountdownOverlay.active === self {
      DelayedCaptureCountdownOverlay.active = nil
    }

    let handler = completion
    completion = nil
    handler?(success)
  }
}

private final class CountdownView: NSView {
  var remainingSeconds: Int = 0

  override func draw(_ dirtyRect: NSRect) {
    let diameter: CGFloat = 160
    let rect = CGRect(
      x: bounds.midX - diameter / 2,
      y: bounds.midY - diameter / 2,
      width: diameter,
      height: diameter
    )

    NSColor.black.withAlphaComponent(0.55).setFill()
    NSBezierPath(ovalIn: rect).fill()

    let text = "\(remainingSeconds)"
    let font = NSFont.systemFont(ofSize: 72, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.white,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let size = attributed.size()
    attributed.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
  }
}
