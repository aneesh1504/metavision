import Foundation
import UIKit

enum ServeNumber: Int, Codable, CaseIterable {
    case first = 1
    case second = 2

    var displayName: String { self == .first ? "1st Serve" : "2nd Serve" }
}

enum ServeOutcome: String, Codable, CaseIterable {
    case inPlay = "in"
    case fault_long = "long"
    case fault_wide = "wide"
    case fault_net = "net"
    case unknown

    var isFault: Bool {
        switch self {
        case .fault_long, .fault_wide, .fault_net: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .inPlay: return "In"
        case .fault_long: return "Long"
        case .fault_wide: return "Wide"
        case .fault_net: return "Net"
        case .unknown: return "Unknown"
        }
    }
}

struct ServeSample: Identifiable, Codable {
    let id: UUID
    let sessionID: UUID
    let timestamp: Date

    // Labels (confirmed by user)
    var serveNumber: ServeNumber
    var outcome: ServeOutcome

    // Analysis
    var metrics: ServeMetrics

    // Reference frame saved as PNG data for overlays.
    // Stored separately on disk; this holds the filename.
    var apexFrameFilename: String?
    var contactFrameFilename: String?

    // Auto-suggestion state (for ASR repair flow)
    var labelSource: LabelSource

    enum LabelSource: String, Codable {
        case userVoice     // user spoke the label
        case userTap       // user tapped the fallback card
        case autoInferred  // auto-inferred (e.g., second after a fault) — not yet confirmed
    }
}
