import SwiftUI

/// Fallback UI sheet shown when ASR fails twice for a single serve.
/// User taps to confirm outcome and serve number.
struct ServeConfirmCard: View {
    let event: ServeDetectionEvent
    let onConfirm: (ServeNumber, ServeOutcome) -> Void

    @State private var serveNumber: ServeNumber = .first
    @State private var outcome: ServeOutcome = .inPlay
    @Environment(\.dismiss) private var dismiss

    init(event: ServeDetectionEvent, onConfirm: @escaping (ServeNumber, ServeOutcome) -> Void) {
        self.event = event
        self.onConfirm = onConfirm
        _serveNumber = State(initialValue: event.suggestedServeNumber)
        _outcome = State(initialValue: event.suggestedOutcome == .unknown ? .inPlay : event.suggestedOutcome)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Confirm this serve")
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Picker("Serve", selection: $serveNumber) {
                            ForEach(ServeNumber.allCases, id: \.self) { n in
                                Text(n.displayName).tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
                    } icon: {
                        Image(systemName: "1.circle")
                    }

                    Label {
                        Picker("Outcome", selection: $outcome) {
                            ForEach(ServeOutcome.allCases, id: \.self) { o in
                                Text(o.displayName).tag(o)
                            }
                        }
                        .pickerStyle(.segmented)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                // Quick metric summary so the user can sanity-check.
                MetricSummaryRow(metrics: event.metrics)

                Spacer()

                Button("Confirm") {
                    onConfirm(serveNumber, outcome)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)

                Button("Skip this serve") { dismiss() }
                    .foregroundStyle(.secondary)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
        }
    }
}

private struct MetricSummaryRow: View {
    let metrics: ServeMetrics

    var body: some View {
        HStack(spacing: 16) {
            MetricChip(
                label: "Toss",
                value: String(format: "%.0f%%", metrics.tossInFrameStability * 100),
                color: metrics.tossInFrameStability > 0.6 ? .green : .orange
            )
            MetricChip(
                label: "Eye",
                value: String(format: "%.0f%%", metrics.eyeOnBallFraction * 100),
                color: metrics.eyeOnBallFraction > 0.6 ? .green : .orange
            )
            MetricChip(
                label: "Type",
                value: metrics.serveTypeGuess.displayName,
                color: .secondary
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MetricChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
