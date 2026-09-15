//
//  CommandPaletteView.swift
//  Snapzy
//
//  A Spotlight-style searchable list of commands (spec §2.27's
//  Command Palette). Typing filters `CommandPaletteAction.all`;
//  Up/Down move the selection, Return runs the selected command and
//  closes the palette, Escape closes without running anything.
//

import SwiftUI

struct CommandPaletteView: View {
  let onSelect: (CommandPaletteAction) -> Void
  let onCancel: () -> Void

  @State private var query = ""
  @State private var selectedIndex = 0
  @FocusState private var searchFieldFocused: Bool

  private var results: [CommandPaletteAction] {
    CommandPaletteAction.matching(query)
  }

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      resultsList
    }
    .frame(width: 480, height: 360)
    .background(.regularMaterial)
    .onAppear { searchFieldFocused = true }
    .onChange(of: query) { _ in selectedIndex = 0 }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Type a command\u{2026}", text: $query)
        .textFieldStyle(.plain)
        .font(.title3)
        .focused($searchFieldFocused)
        .onSubmit(runSelection)
    }
    .padding(14)
    .background(KeyCaptureView(onKeyDown: handleKeyDown))
  }

  private var resultsList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
            row(for: result, isSelected: index == selectedIndex)
              .id(index)
              .onTapGesture {
                selectedIndex = index
                runSelection()
              }
          }
          if results.isEmpty {
            Text("No matching commands")
              .foregroundStyle(.secondary)
              .padding()
          }
        }
      }
      .onChange(of: selectedIndex) { newValue in
        proxy.scrollTo(newValue, anchor: .center)
      }
    }
  }

  private func row(for result: CommandPaletteAction, isSelected: Bool) -> some View {
    HStack(spacing: 10) {
      Image(systemName: result.systemImage)
        .frame(width: 20)
      Text(result.title)
      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    .contentShape(Rectangle())
  }

  private func handleKeyDown(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 125:  // Down arrow
      guard !results.isEmpty else { return true }
      selectedIndex = min(selectedIndex + 1, results.count - 1)
      return true
    case 126:  // Up arrow
      guard !results.isEmpty else { return true }
      selectedIndex = max(selectedIndex - 1, 0)
      return true
    case 53:  // Escape
      onCancel()
      return true
    default:
      return false
    }
  }

  private func runSelection() {
    guard results.indices.contains(selectedIndex) else { return }
    onSelect(results[selectedIndex])
  }
}

/// An invisible `NSView` that intercepts arrow-key/Escape `keyDown`
/// events before SwiftUI's `TextField` swallows them, since `TextField`
/// has no built-in way to observe arrow keys while retaining focus.
private struct KeyCaptureView: NSViewRepresentable {
  let onKeyDown: (NSEvent) -> Bool

  func makeNSView(context: Context) -> KeyCaptureNSView {
    let view = KeyCaptureNSView()
    view.onKeyDown = onKeyDown
    return view
  }

  func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
    nsView.onKeyDown = onKeyDown
  }
}

private final class KeyCaptureNSView: NSView {
  var onKeyDown: ((NSEvent) -> Bool)?
  private var monitor: Any?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.window != nil else { return event }
      return (self.onKeyDown?(event) ?? false) ? nil : event
    }
  }

  deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
