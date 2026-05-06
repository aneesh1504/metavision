import Foundation

/// Deterministic rules-based feedback engine.
/// Takes confirmed serve samples for a session and produces a ServeBatchReport.
struct FeedbackEngine {

    static func generateReport(
        samples: [ServeSample],
        sessionID: UUID,
        screenshotFilenames: [String]
    ) -> ServeBatchReport {
        let firstServes = samples.filter { $0.serveNumber == .first }
        let secondServes = samples.filter { $0.serveNumber == .second }

        let firstStats = firstServes.isEmpty ? nil : computeStats(for: firstServes)
        let secondStats = secondServes.isEmpty ? nil : computeStats(for: secondServes)

        var findings: [ServeFinding] = []
        findings += tossFindingsFor(firstStats, serveLabel: "first-serve")
        findings += tossFindingsFor(secondStats, serveLabel: "second-serve")
        findings += comparisonFindings(first: firstStats, second: secondStats)
        findings += eyeOnBallFindings(samples: samples)

        // Keep at most 3 findings; prefer actionable > caution > positive.
        let ranked = findings.sorted { $0.severity.rank > $1.severity.rank }
        let top = Array(ranked.prefix(3))

        return ServeBatchReport(
            id: UUID(),
            sessionID: sessionID,
            generatedAt: Date(),
            sampleCount: samples.count,
            firstServeStats: firstStats,
            secondServeStats: secondStats,
            findings: top,
            screenshotFilenames: screenshotFilenames
        )
    }

    // MARK: - Stats

    private static func computeStats(for samples: [ServeSample]) -> ServeGroupStats {
        let metrics = samples.map(\.metrics)
        let faults = samples.filter { $0.outcome.isFault }.count
        let serveTypeCounts = Dictionary(grouping: metrics.map { $0.serveTypeGuess.rawValue }, by: { $0 })
            .mapValues(\.count)

        return ServeGroupStats(
            count: samples.count,
            faultCount: faults,
            avgTossStability: average(metrics.map(\.tossInFrameStability)),
            avgEyeOnBall: average(metrics.map(\.eyeOnBallFraction)),
            avgLateralDrift: average(metrics.map(\.lateralDrift)),
            apexXValues: metrics.map(\.tossApexNormalizedX),
            apexYValues: metrics.map(\.tossApexNormalizedY),
            serveTypeBreakdown: serveTypeCounts
        )
    }

    // MARK: - Rules

    private static func tossFindingsFor(_ stats: ServeGroupStats?, serveLabel: String) -> [ServeFinding] {
        guard let stats, stats.count >= 2 else { return [] }
        var findings: [ServeFinding] = []

        if stats.avgTossStability < 0.6 {
            findings.append(ServeFinding(
                id: UUID(),
                metricKey: "tossStability",
                severity: stats.avgTossStability < 0.4 ? .actionable : .caution,
                text: "Your \(serveLabel) toss varies significantly across your \(stats.count) serves. "
                    + "Your best serves had a much tighter arc. Focus on a single repeatable release point.",
                drillIDs: ["toss_stability_shadow", "toss_arc_wall"]
            ))
        } else {
            findings.append(ServeFinding(
                id: UUID(),
                metricKey: "tossStability",
                severity: .positive,
                text: "Your \(serveLabel) toss arc was consistent across this batch — good work.",
                drillIDs: []
            ))
        }

        if stats.faultRate > 0.5 && stats.count >= 3 {
            findings.append(ServeFinding(
                id: UUID(),
                metricKey: "faultRate",
                severity: .actionable,
                text: "\(Int(stats.faultRate * 100))% of your \(serveLabel)s were faults in this batch. "
                    + "Check the contact frame overlay — your fault serves may share a toss position.",
                drillIDs: ["slow_motion_trophy"]
            ))
        }

        return findings
    }

    private static func comparisonFindings(first: ServeGroupStats?, second: ServeGroupStats?) -> [ServeFinding] {
        guard let first, let second, first.count >= 2, second.count >= 2 else { return [] }
        var findings: [ServeFinding] = []

        let driftDiff = abs(second.avgLateralDrift - first.avgLateralDrift)
        if driftDiff > 0.08 {
            let direction = second.avgLateralDrift > first.avgLateralDrift ? "further left" : "further right"
            findings.append(ServeFinding(
                id: UUID(),
                metricKey: "lateralDriftComparison",
                severity: .actionable,
                text: "Your second-serve toss drifts \(direction) compared to your first serve. "
                    + "On \(second.faultCount) of \(second.count) second-serve faults, that drift was most pronounced.",
                drillIDs: ["toss_arc_wall", "second_serve_routine"]
            ))
        }

        let routineRush = second.avgEyeOnBall < first.avgEyeOnBall - 0.15
        if routineRush {
            findings.append(ServeFinding(
                id: UUID(),
                metricKey: "secondServeRushed",
                severity: .caution,
                text: "You're watching the ball less on your second serves. This often means a rushed routine. "
                    + "Use the 3-bounce reset to re-establish your rhythm.",
                drillIDs: ["second_serve_routine"]
            ))
        }

        return findings
    }

    private static func eyeOnBallFindings(samples: [ServeSample]) -> [ServeFinding] {
        let avg = average(samples.map(\.metrics.eyeOnBallFraction))
        guard avg < 0.6 else { return [] }
        return [ServeFinding(
            id: UUID(),
            metricKey: "eyeOnBall",
            severity: .actionable,
            text: "The ball left your field of view early on most serves — you're dropping your gaze before contact. "
                + "Try the coin-on-racket drill to build the habit of watching through contact.",
            drillIDs: ["eyes_on_ball_coin"]
        )]
    }

    // MARK: - Helpers

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

private extension ServeFinding.Severity {
    var rank: Int {
        switch self {
        case .actionable: return 2
        case .caution: return 1
        case .positive: return 0
        }
    }
}
