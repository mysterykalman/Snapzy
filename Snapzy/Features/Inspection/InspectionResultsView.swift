//
//  InspectionResultsView.swift
//  Snapzy
//
//  Displays AuditFindings that have arrived over the browser bridge
//  (InspectionFindingsStore) -- the first UI to actually show
//  AccessibilityAuditMapper/EcommerceAuditMapper output to a user.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Spec §2.25's "Audit board views: by page / category / severity /
/// status" -- findings can be grouped along any one of these four axes
/// rather than only severity.
enum InspectionFindingGrouping: String, CaseIterable, Identifiable {
  case severity = "Severity"
  case category = "Category"
  case page = "Page"
  case status = "Status"

  var id: String { rawValue }

  func key(for finding: AuditFinding) -> String {
    switch self {
    case .severity: return finding.severity
    case .category: return finding.category
    case .page: return finding.page
    case .status: return finding.status.rawValue
    }
  }

  /// Preferred group ordering for this axis, when known (severity has
  /// a meaningful default order; page/category/status groups are
  /// simply sorted alphabetically since there's no universal ranking).
  var preferredOrder: [String]? {
    switch self {
    case .severity: return AuditFinding.DefaultSeverity.all
    case .category, .page, .status: return nil
    }
  }
}

struct InspectionResultsView: View {
  @ObservedObject var store: InspectionFindingsStore
  @State private var grouping: InspectionFindingGrouping = .severity

  private var groupedFindings: [(key: String, findings: [AuditFinding])] {
    let grouped = Dictionary(grouping: store.findings) { grouping.key(for: $0) }
    let orderedKeys: [String]
    if let preferredOrder = grouping.preferredOrder {
      orderedKeys = preferredOrder.filter { grouped[$0] != nil }
    } else {
      orderedKeys = grouped.keys.sorted()
    }
    return orderedKeys.map { ($0, grouped[$0] ?? []) }
  }

  private var hasAnyResults: Bool {
    !store.findings.isEmpty || !store.technologyDetections.isEmpty
      || !store.componentDetections.isEmpty || store.shopifyTheme != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      if !hasAnyResults {
        emptyState
      } else {
        List {
          ForEach(groupedFindings, id: \.key) { group in
            Section(group.key) {
              ForEach(group.findings) { finding in
                FindingRow(finding: finding)
              }
            }
          }
          if !store.technologyDetections.isEmpty {
            Section("Technology Detected") {
              ForEach(store.technologyDetections, id: \.technology) { detection in
                Text("\(detection.technology) (\(detection.confidence) confidence)")
                  .font(.callout)
              }
            }
          }
          if !store.componentDetections.isEmpty {
            Section("Components Detected") {
              ForEach(store.componentDetections, id: \.selector) { detection in
                VStack(alignment: .leading, spacing: 2) {
                  Text("\(detection.component) (\(detection.confidence) confidence)")
                    .font(.callout)
                  Text(detection.selector)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
              }
            }
          }
          if let shopifyTheme = store.shopifyTheme {
            Section("Shopify Theme") {
              if let name = shopifyTheme.themeName {
                Text("Theme: \(name)").font(.callout)
              }
              if let templateType = shopifyTheme.templateType {
                Text("Template: \(templateType)").font(.callout)
              }
              if !shopifyTheme.sectionIds.isEmpty {
                Text("Sections: \(shopifyTheme.sectionIds.joined(separator: ", "))")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }
        .listStyle(.inset)
      }
    }
    .frame(minWidth: 480, minHeight: 360)
  }

  private var header: some View {
    HStack {
      Text("Inspection Results")
        .font(.headline)
      Spacer()
      Text("\(store.findings.count) finding\(store.findings.count == 1 ? "" : "s")")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Picker("Group by", selection: $grouping) {
        ForEach(InspectionFindingGrouping.allCases) { grouping in
          Text(grouping.rawValue).tag(grouping)
        }
      }
      .labelsHidden()
      .fixedSize()
      Menu {
        Button("Export as Markdown") { exportReport(format: .markdown) }
        Button("Export as HTML") { exportReport(format: .html) }
      } label: {
        Label("Export Report", systemImage: "square.and.arrow.up")
      }
      .disabled(store.findings.isEmpty)
      .fixedSize()
      Button("Clear") {
        store.clear()
      }
      .disabled(!hasAnyResults)
    }
    .padding()
  }

  private enum ReportFormat {
    case markdown
    case html

    var contentType: UTType {
      switch self {
      case .markdown: return UTType(filenameExtension: "md") ?? .plainText
      case .html: return .html
      }
    }

    var defaultFileName: String {
      switch self {
      case .markdown: return "Inspection Report.md"
      case .html: return "Inspection Report.html"
      }
    }
  }

  private func exportReport(format: ReportFormat) {
    let content: String
    switch format {
    case .markdown: content = AuditReport.renderMarkdown(findings: store.findings)
    case .html: content = AuditReport.renderHTML(findings: store.findings)
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [format.contentType]
    panel.nameFieldStringValue = format.defaultFileName
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      DiagnosticLogger.shared.logError(.action, error, "Inspection report export failed")
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Spacer()
      Text("No inspection results yet")
        .font(.title3)
      Text("Run an accessibility or ecommerce audit from the Capture browser extension's toolbar or keyboard shortcut to see results here.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

private struct FindingRow: View {
  let finding: AuditFinding

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(finding.title)
          .font(.body.weight(.semibold))
        Spacer()
        Text(finding.category)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Text(finding.finding)
        .font(.callout)
      if !finding.recommendation.isEmpty {
        Text(finding.recommendation)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Text(finding.page)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
  }
}
