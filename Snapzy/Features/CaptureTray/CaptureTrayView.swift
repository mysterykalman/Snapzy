//
//  CaptureTrayView.swift
//  Snapzy
//
//  Shows the Capture Tray's contents (thumbnail + filename per item),
//  lets the user reorder/remove them, and hands the whole ordered list
//  to Annotate's existing Combine Images flow on "Assemble" -- reusing
//  that already-real, already-tested multi-image canvas rather than
//  building a second one.
//

import AppKit
import SwiftUI

struct CaptureTrayView: View {
  @ObservedObject var store: CaptureTrayStore
  let onAssemble: ([URL]) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      if store.items.isEmpty {
        emptyState
      } else {
        List {
          ForEach(store.items, id: \.self) { url in
            CaptureTrayRow(url: url) {
              store.remove(url)
            }
          }
          .onMove { indices, newOffset in
            store.move(fromOffsets: indices, toOffset: newOffset)
          }
        }
        .listStyle(.inset)
      }
    }
    .frame(minWidth: 420, minHeight: 320)
  }

  private var header: some View {
    HStack {
      Text("Capture Tray")
        .font(.headline)
      Spacer()
      Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button("Assemble") {
        onAssemble(store.items)
      }
      .disabled(!store.canAssemble)
      Button("Clear") {
        store.clear()
      }
      .disabled(store.items.isEmpty)
    }
    .padding()
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Spacer()
      Text("Capture Tray is empty")
        .font(.title3)
      Text("Add captures from History (right-click \u{2192} Add to Capture Tray), then Assemble them into one canvas.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

private struct CaptureTrayRow: View {
  let url: URL
  let onRemove: () -> Void

  @State private var thumbnail: NSImage?

  var body: some View {
    HStack(spacing: 10) {
      Group {
        if let thumbnail {
          Image(nsImage: thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Color.secondary.opacity(0.15)
        }
      }
      .frame(width: 44, height: 44)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

      Text(url.lastPathComponent)
        .font(.callout)
        .lineLimit(1)

      Spacer()

      Button {
        onRemove()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 4)
    .task {
      thumbnail = NSImage(contentsOf: url)
    }
  }
}
