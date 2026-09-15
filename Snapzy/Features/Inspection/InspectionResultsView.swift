//
//  InspectionResultsView.swift
//  Snapzy
//
//  Displays AuditFindings that have arrived over the browser bridge
//  (InspectionFindingsStore) -- the first UI to actually show
//  AccessibilityAuditMapper/EcommerceAuditMapper output to a user.
//

import SwiftUI

struct InspectionResultsView: View {
  @ObservedObject var store: InspectionFindingsStore

  private var findingsBySeverity: [(severity: String, findings: [AuditFinding])] {
    let grouped = Dictionary(grouping: store.findings, by: \.severity)
    return AuditFinding.DefaultSeverity.all
      .filter { grouped[$0] != nil }
      .map { ($0, grouped[$0] ?? []) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      if store.findings.isEmpty && store.technologyDetections.isEmpty {
        emptyState
      } else {
        List {
          ForEach(findingsBySeverity, id: \.severity) { group in
            Section(group.severity) {
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
      Button("Clear") {
        store.clear()
      }
      .disabled(store.findings.isEmpty && store.technologyDetections.isEmpty)
    }
    .padding()
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
