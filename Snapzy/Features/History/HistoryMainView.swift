//
//  HistoryMainView.swift
//  Snapzy
//
//  Root SwiftUI view for the capture history browser
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct HistoryMainView: View {
  @ObservedObject private var themeManager = ThemeManager.shared
  @ObservedObject private var store = CaptureHistoryStore.shared
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @StateObject private var viewModel = HistorySearchViewModel()
  @State private var selectedIds: Set<UUID> = []

  private var filteredRecords: [CaptureHistoryRecord] {
    viewModel.filteredRecords
  }

  private var filteredRecordIDs: [UUID] {
    filteredRecords.map(\.id)
  }

  var body: some View {
    ZStack {
      HistoryBackdropView(style: backgroundStyle)
        .ignoresSafeArea()

      VStack(spacing: 18) {
        HistoryToolbar(
          searchText: $viewModel.searchText,
          selectedCount: selectedRecords.count,
          canSelectAll: selectedRecords.count < filteredRecords.count,
          onSelectAll: selectAllFilteredRecords,
          onClearSelection: { selectedIds.removeAll() },
          onDeleteSelection: deleteSelectedRecords,
          onExportSelectionAsPDF: { exportSelectedRecords(as: .pdf) },
          onExportSelectionAsPowerPoint: { exportSelectedRecords(as: .pptx) },
          onExportSelectionAsContactSheet: exportSelectedRecordsAsContactSheet
        )

        HistoryFilterBar(
          selectedFilter: $viewModel.selectedFilter,
          counts: filterCounts
        )

        if filteredRecords.isEmpty {
          HistoryEmptyStateView(
            filter: viewModel.selectedFilter,
            hasSearch: !viewModel.searchText.isEmpty
          )
        } else {
          HistoryGridView(
            records: filteredRecords,
            selectedIds: $selectedIds
          )
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 20)
    }
    .preferredColorScheme(themeManager.systemAppearance)
    .onReceive(NotificationCenter.default.publisher(for: .historyCopySelection)) { notification in
      guard notification.object is HistoryWindow else { return }
      copySelectedRecords()
    }
    .onReceive(NotificationCenter.default.publisher(for: .historyDeleteSelection)) { notification in
      guard notification.object is HistoryWindow else { return }
      deleteSelectedRecords()
    }
    .onReceive(NotificationCenter.default.publisher(for: .historySelectAll)) { notification in
      guard notification.object is HistoryWindow else { return }
      selectAllFilteredRecords()
    }
    .onChange(of: filteredRecordIDs) { ids in
      selectedIds.formIntersection(Set(ids))
    }
  }

  private var filterCounts: [CaptureHistoryType?: Int] {
    var counts: [CaptureHistoryType?: Int] = [:]
    counts[nil] = store.records.count
    counts[.screenshot] = store.records.filter { $0.captureType == .screenshot }.count
    counts[.video] = store.records.filter { $0.captureType == .video }.count
    counts[.gif] = store.records.filter { $0.captureType == .gif }.count
    return counts
  }

  private var selectedRecords: [CaptureHistoryRecord] {
    filteredRecords.filter { selectedIds.contains($0.id) }
  }

  private func copySelectedRecords() {
    HistoryWindowController.shared.copyToClipboard(selectedRecords)
  }

  private func selectAllFilteredRecords() {
    selectedIds = Set(filteredRecords.map(\.id))
  }

  private func deleteSelectedRecords() {
    let deletedCount = HistoryWindowController.shared.deleteRecords(
      selectedRecords,
      asksConfirmation: true
    )
    guard deletedCount > 0 else { return }
    selectedIds.removeAll()
  }

  /// Loads each selected screenshot/GIF record's full-resolution image
  /// (skipping video records, which have no single still frame to
  /// export) and writes them as one PDF or PowerPoint deck, one
  /// page/slide per capture in selection order.
  private func exportSelectedRecords(as format: HistoryExportFormat) {
    let images: [CGImage] = selectedRecords.compactMap { record in
      guard record.captureType != .video else { return nil }
      return NSImage(contentsOfFile: record.filePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    guard !images.isEmpty else { return }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [format.contentType]
    panel.nameFieldStringValue = format.defaultFileName
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      switch format {
      case .pdf: try PDFExport.write(images: images, to: url)
      case .pptx: try PPTXExport.write(images: images, to: url)
      }
    } catch {
      DiagnosticLogger.shared.logError(.history, error, "History selection export failed", context: ["format": format.defaultFileName])
    }
  }

  /// Composes every selected screenshot/GIF into one contact-sheet image
  /// (grid layout, filename labels) via `ContactSheetGenerator` -- the
  /// first UI caller of that generator, which was previously fully
  /// implemented and tested but unreachable from anywhere in the app.
  private func exportSelectedRecordsAsContactSheet() {
    let labeledImages: [(image: CGImage, label: String)] = selectedRecords.compactMap { record in
      guard record.captureType != .video,
        let image = NSImage(contentsOfFile: record.filePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
      else { return nil }
      return (image, record.fileName)
    }
    guard !labeledImages.isEmpty else { return }

    let columns = max(1, Int(Double(labeledImages.count).squareRoot().rounded(.up)))
    guard
      let contactSheet = ContactSheetGenerator.generate(
        images: labeledImages.map(\.image),
        layout: .grid(columns: columns),
        labels: labeledImages.map(\.label)
      )
    else { return }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "Contact Sheet.png"
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else { return }

    guard
      let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, contactSheet, nil)
    if !CGImageDestinationFinalize(destination) {
      DiagnosticLogger.shared.log(.warning, .history, "Contact sheet export failed to finalize PNG")
    }
  }
}

private enum HistoryExportFormat {
  case pdf
  case pptx

  var contentType: UTType {
    switch self {
    case .pdf: return .pdf
    case .pptx: return UTType(filenameExtension: "pptx") ?? .data
    }
  }

  var defaultFileName: String {
    switch self {
    case .pdf: return "Captures.pdf"
    case .pptx: return "Captures.pptx"
    }
  }
}

struct HistoryBackdropView: View {
  let style: HistoryBackgroundStyle
  var cornerRadius: CGFloat = 0
  var compact = false

  @ObservedObject private var themeManager = ThemeManager.shared
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      if compact {
        switch style {
        case .hud:
          Color(white: 0.15)
        case .solid:
          Color(nsColor: WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance))
        }
      } else {
        switch style {
        case .hud:
          Rectangle().fill(.ultraThinMaterial)
          Rectangle().fill(hudTint)
          glow(color: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.38), width: 220, height: 220, x: -170, y: -120)
          glow(color: Color.black.opacity(colorScheme == .dark ? 0.08 : 0.03), width: 240, height: 240, x: 180, y: 130)
        case .solid:
          Color(nsColor: WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance))
        }

        if style == .hud {
          Rectangle()
            .fill(surfaceTint)
        }
      }

      if compact {
        compactPreviewOverlay
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private var hudTint: LinearGradient {
    LinearGradient(
      colors: colorScheme == .dark
        ? [
          Color.white.opacity(0.05),
          Color.black.opacity(0.12),
          Color.white.opacity(0.03),
        ]
        : [
          Color.white.opacity(0.18),
          Color.black.opacity(0.05),
          Color.white.opacity(0.12),
        ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var surfaceTint: LinearGradient {
    LinearGradient(
      colors: [
        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.24),
        Color.clear,
        Color.black.opacity(colorScheme == .dark ? 0.1 : 0.03),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var compactPreviewOverlay: some View {
    VStack(spacing: 0) {
      // Header: traffic lights, miniature filter pills, and circular action button
      HStack(spacing: 0) {
        HStack(spacing: 3) {
          Circle().fill(Color.red.opacity(0.9)).frame(width: 3.5, height: 3.5)
          Circle().fill(Color.yellow.opacity(0.9)).frame(width: 3.5, height: 3.5)
          Circle().fill(Color.green.opacity(0.9)).frame(width: 3.5, height: 3.5)
        }
        .padding(.leading, 6)

        Spacer()

        HStack(spacing: 3) {
          Capsule()
            .fill(Color.accentColor)
            .frame(width: 10, height: 5)
          Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .frame(width: 10, height: 5)
          Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .frame(width: 10, height: 5)
        }

        Spacer()

        Circle()
          .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
          .frame(width: 5, height: 5)
          .padding(.trailing, 6)
      }
      .frame(height: 14)
      .background(previewToolbarFill)

      // Content area: Symmetrical grid of capture items (landscape screenshot cards)
      HStack(spacing: 6) {
        ForEach(0..<3, id: \.self) { index in
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(previewCardFill.opacity(index == 0 ? 1.0 : 0.68))
            .frame(width: 16, height: 26)
            .overlay(
              RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(previewWindowStroke, lineWidth: 0.5)
            )
        }
      }
      .padding(.horizontal, 6)
      .padding(.top, 6)

      Spacer(minLength: 0)
    }
  }

  private var previewCardFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.78)
  }

  private var previewWindowStroke: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }

  private var previewToolbarFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
  }

  private func glow(color: Color, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
    Ellipse()
      .fill(color)
      .frame(width: width, height: height)
      .blur(radius: compact ? 18 : 90)
      .offset(x: x, y: y)
  }
}
