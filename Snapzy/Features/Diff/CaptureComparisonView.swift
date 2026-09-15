//
//  CaptureComparisonView.swift
//  Snapzy
//
//  The first UI consumer of Snapzy/Services/Diff's visual-diff engine
//  (ImageDiff/PageLayoutDiff/etc, ported this session) -- previously a
//  fully-built, fully-tested subsystem with no way for a user to
//  actually invoke it. Presents two captures (typically two History
//  selections) side by side, overlaid with an opacity slider, swiped
//  with a draggable divider, or diffed pixel-for-pixel/perceptually.
//

import AppKit
import SwiftUI

enum CaptureComparisonMode: String, CaseIterable, Identifiable {
  case sideBySide = "Side by Side"
  case overlay = "Overlay"
  case swipe = "Swipe"
  case pixelDiff = "Pixel Diff"
  case perceptualDiff = "Perceptual Diff"

  var id: String { rawValue }

  /// Every mode but side-by-side needs matching dimensions, since
  /// ImageDiff's overlay/swipe/pixelDiff/perceptualDiff all composite
  /// pixel-for-pixel into one shared canvas.
  var requiresMatchingDimensions: Bool { self != .sideBySide }
}

struct CaptureComparisonView: View {
  let before: CGImage
  let beforeLabel: String
  let after: CGImage
  let afterLabel: String

  @State private var mode: CaptureComparisonMode = .sideBySide
  @State private var opacity: Double = 0.5
  @State private var dividerFraction: Double = 0.5

  private var dimensionsMatch: Bool {
    before.width == after.width && before.height == after.height
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
      Divider()
      controls
    }
    .frame(minWidth: 640, minHeight: 480)
  }

  private var header: some View {
    HStack {
      Text("Compare Captures")
        .font(.headline)
      Spacer()
      Picker("Mode", selection: $mode) {
        ForEach(CaptureComparisonMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .fixedSize()
    }
    .padding()
  }

  @ViewBuilder
  private var content: some View {
    if mode.requiresMatchingDimensions && !dimensionsMatch {
      mismatchedDimensionsMessage
    } else {
      switch mode {
      case .sideBySide:
        sideBySideView
      case .overlay:
        overlayView
      case .swipe:
        swipeView
      case .pixelDiff:
        diffView(kind: .pixel)
      case .perceptualDiff:
        diffView(kind: .perceptual)
      }
    }
  }

  private var mismatchedDimensionsMessage: some View {
    VStack(spacing: 8) {
      Text("These captures are different sizes")
        .font(.title3)
      Text("\(beforeLabel): \(before.width)\u{00D7}\(before.height) px \u{00B7} \(afterLabel): \(after.width)\u{00D7}\(after.height) px")
        .font(.callout)
        .foregroundStyle(.secondary)
      Text("\(mode.rawValue) needs both captures at the same pixel size. Try Side by Side instead.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var sideBySideView: some View {
    HStack(spacing: 12) {
      labeledImage(before, label: beforeLabel)
      labeledImage(after, label: afterLabel)
    }
    .padding()
  }

  private func labeledImage(_ image: CGImage, label: String) -> some View {
    VStack(spacing: 6) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
        .resizable()
        .aspectRatio(contentMode: .fit)
    }
  }

  private var overlayView: some View {
    VStack(spacing: 12) {
      if let composited = try? ImageDiff.overlay(before: before, after: after, opacity: opacity) {
        Image(nsImage: NSImage(cgImage: composited, size: NSSize(width: composited.width, height: composited.height)))
          .resizable()
          .aspectRatio(contentMode: .fit)
      }
    }
    .padding()
  }

  private var swipeView: some View {
    VStack(spacing: 12) {
      if let composited = try? ImageDiff.swipe(before: before, after: after, dividerFraction: dividerFraction) {
        Image(nsImage: NSImage(cgImage: composited, size: NSSize(width: composited.width, height: composited.height)))
          .resizable()
          .aspectRatio(contentMode: .fit)
      }
    }
    .padding()
  }

  private enum DiffKind {
    case pixel
    case perceptual
  }

  private func diffView(kind: DiffKind) -> some View {
    let result: ImageDiff.Result?
    switch kind {
    case .pixel: result = try? ImageDiff.pixelDiff(before: before, after: after)
    case .perceptual: result = try? ImageDiff.perceptualDiff(before: before, after: after)
    }

    return VStack(spacing: 8) {
      if let result {
        Text("\(String(format: "%.1f", result.differingRatio * 100))% differs")
          .font(.callout)
          .foregroundStyle(.secondary)
        Image(nsImage: NSImage(cgImage: result.diffImage, size: NSSize(width: result.diffImage.width, height: result.diffImage.height)))
          .resizable()
          .aspectRatio(contentMode: .fit)
      }
    }
    .padding()
  }

  @ViewBuilder
  private var controls: some View {
    switch mode {
    case .overlay:
      HStack {
        Text("Opacity")
          .font(.caption)
        Slider(value: $opacity, in: 0...1)
      }
      .padding()
    case .swipe:
      HStack {
        Text("Divider")
          .font(.caption)
        Slider(value: $dividerFraction, in: 0...1)
      }
      .padding()
    case .sideBySide, .pixelDiff, .perceptualDiff:
      EmptyView()
    }
  }
}
