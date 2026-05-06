import Foundation

struct ServeFinding: Identifiable, Codable {
    let id: UUID
    let metricKey: String        // e.g. "tossStability", "eyeOnBall"
    let severity: Severity
    let text: String             // human-readable coaching statement
    let drillIDs: [String]       // IDs from Drills.json

    enum Severity: String, Codable {
        case positive    // reinforces a good pattern
        case caution     // variance worth watching
        case actionable  // clear issue with a drill suggestion
    }
}

struct ServeGroupStats: Codable {
    let count: Int
    let faultCount: Int
    var faultRate: Double { count > 0 ? Double(faultCount) / Double(count) : 0 }

    let avgTossStability: Double
    let avgEyeOnBall: Double
    let avgLateralDrift: Double
    let apexXValues: [Double]
    let apexYValues: [Double]
    let serveTypeBreakdown: [String: Int]   // ServeTypeGuess.rawValue → count
}

struct ServeBatchReport: Identifiable, Codable {
    let id: UUID
    let sessionID: UUID
    let generatedAt: Date

    let sampleCount: Int
    let firstServeStats: ServeGroupStats?
    let secondServeStats: ServeGroupStats?
    let findings: [ServeFinding]

    // Filenames of annotated PNG frames saved to disk.
    let screenshotFilenames: [String]

    var drillIDs: [String] {
        findings.flatMap(\.drillIDs).unique()
    }
}

private extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
