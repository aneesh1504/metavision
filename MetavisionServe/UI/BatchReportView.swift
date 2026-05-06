import SwiftUI

struct BatchReportView: View {
    @EnvironmentObject var practiceStore: PracticeStore
    @State private var selectedReport: ServeBatchReport?

    var body: some View {
        NavigationStack {
            Group {
                if practiceStore.reports.isEmpty {
                    emptyState
                } else {
                    reportList
                }
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $selectedReport) { report in
            ReportDetailView(report: report, store: practiceStore)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No reports yet")
                .font(.title3.weight(.semibold))
            Text("Complete 5 confirmed serves to generate your first batch report.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var reportList: some View {
        List(practiceStore.reports) { report in
            Button {
                selectedReport = report
            } label: {
                ReportRowView(report: report)
            }
            .listRowBackground(Color(.secondarySystemBackground))
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Report Row

private struct ReportRowView: View {
    let report: ServeBatchReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(report.sampleCount) serves")
                    .font(.headline)
                Spacer()
                Text(report.generatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let finding = report.findings.first(where: { $0.severity == .actionable }) {
                Text(finding.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Report Detail

struct ReportDetailView: View {
    let report: ServeBatchReport
    let store: PracticeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Stats summary cards
                    statsSection

                    // Findings
                    if !report.findings.isEmpty {
                        findingsSection
                    }

                    // Drills
                    let drillIDs = report.drillIDs
                    if !drillIDs.isEmpty {
                        drillsSection(ids: drillIDs)
                    }

                    // Screenshots
                    if !report.screenshotFilenames.isEmpty {
                        screenshotSection
                    }
                }
                .padding()
            }
            .navigationTitle("Batch Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Batch")
                .font(.headline)

            HStack(spacing: 12) {
                if let first = report.firstServeStats {
                    StatCard(title: "1st Serve", stats: first)
                }
                if let second = report.secondServeStats {
                    StatCard(title: "2nd Serve", stats: second)
                }
            }
        }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Findings")
                .font(.headline)
            ForEach(report.findings) { finding in
                FindingCard(finding: finding)
            }
        }
    }

    private func drillsSection(ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested Drills")
                .font(.headline)
            ForEach(loadDrills(ids: ids), id: \.id) { drill in
                DrillCard(drill: drill)
            }
        }
    }

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Frame Analysis")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(report.screenshotFilenames, id: \.self) { filename in
                        if let image = store.loadFrame(filename: filename) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private func loadDrills(ids: [String]) -> [Drill] {
        DrillLibrary.shared.drills(for: ids)
    }
}

// MARK: - Sub-views

private struct StatCard: View {
    let title: String
    let stats: ServeGroupStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            metricRow("Toss stability", value: String(format: "%.0f%%", stats.avgTossStability * 100))
            metricRow("Eye on ball", value: String(format: "%.0f%%", stats.avgEyeOnBall * 100))
            metricRow("Fault rate", value: String(format: "%.0f%%", stats.faultRate * 100))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium))
        }
    }
}

private struct FindingCard: View {
    let finding: ServeFinding

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            severityIcon
            Text(finding.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var severityIcon: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .font(.body.weight(.semibold))
    }

    private var iconName: String {
        switch finding.severity {
        case .positive: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .actionable: return "arrow.right.circle.fill"
        }
    }

    private var iconColor: Color {
        switch finding.severity {
        case .positive: return .green
        case .caution: return .orange
        case .actionable: return .blue
        }
    }

    private var cardBackground: Color {
        switch finding.severity {
        case .positive: return Color.green.opacity(0.08)
        case .caution: return Color.orange.opacity(0.08)
        case .actionable: return Color.blue.opacity(0.08)
        }
    }
}

private struct DrillCard: View {
    let drill: Drill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(drill.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(drill.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(drill.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
