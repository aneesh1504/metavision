import Foundation

enum ServeTypeGuess: String, Codable {
    case flatLike = "flat-like"
    case sliceLike = "slice-like"
    case kickLike = "kick-like"
    case unknown

    var displayName: String {
        switch self {
        case .flatLike: return "Flat-ish"
        case .sliceLike: return "Slice-ish"
        case .kickLike: return "Kick-ish"
        case .unknown: return "Unknown"
        }
    }
}

struct TrackingQuality: Codable {
    let detectedFrames: Int
    let totalFrames: Int
    var fraction: Double { Double(detectedFrames) / max(1, Double(totalFrames)) }

    var isAcceptable: Bool { fraction >= 0.4 }
}

struct ServeMetrics: Codable {
    /// Ball apex position in normalized coordinates (0–1, UIKit convention: y=0 is top).
    let tossApexNormalizedX: Double
    let tossApexNormalizedY: Double

    /// 0 = very inconsistent, 1 = perfectly stable.
    let tossInFrameStability: Double

    /// Horizontal drift from toss release to apex. Positive = rightward (for right-handers, toward the court).
    let lateralDrift: Double

    /// Fraction of toss frames where the ball was detected (eye-on-ball proxy).
    let eyeOnBallFraction: Double

    /// Ball position at estimated contact.
    let contactNormalizedX: Double
    let contactNormalizedY: Double

    /// Qualitative serve type inferred from post-contact trajectory.
    let serveTypeGuess: ServeTypeGuess

    let trackingQuality: TrackingQuality

    static let empty = ServeMetrics(
        tossApexNormalizedX: 0,
        tossApexNormalizedY: 0,
        tossInFrameStability: 0,
        lateralDrift: 0,
        eyeOnBallFraction: 0,
        contactNormalizedX: 0,
        contactNormalizedY: 0,
        serveTypeGuess: .unknown,
        trackingQuality: TrackingQuality(detectedFrames: 0, totalFrames: 0)
    )
}
