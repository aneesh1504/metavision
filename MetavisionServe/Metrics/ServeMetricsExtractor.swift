import UIKit

/// Extracts ServeMetrics from a clip (ordered array of frames + timestamps).
/// Must be called on a background thread — blocks until Vision processing completes.
struct ServeMetricsExtractor {

    static func extract(from frames: [(image: UIImage, timestamp: Date)]) -> ServeMetrics {
        let tracker = BallTracker()

        // Process frames sequentially so we preserve temporal order for velocity.
        var observations: [(obs: BallObservation, ts: Date)] = []
        for (image, ts) in frames {
            if let obs = tracker.detect(in: image) {
                observations.append((obs, ts))
            }
        }

        return compute(from: observations, totalFrames: frames.count)
    }

    // MARK: - Computation

    private static func compute(
        from observations: [(obs: BallObservation, ts: Date)],
        totalFrames: Int
    ) -> ServeMetrics {
        guard !observations.isEmpty else { return ServeMetrics.empty }

        let ys = observations.map { $0.obs.normalizedY }
        let xs = observations.map { $0.obs.normalizedX }

        // Apex: the frame where the ball is highest (lowest y in UIKit coords).
        let apexIndex = ys.indices.min(by: { ys[$0] < ys[$1] }) ?? 0

        // Toss stability: std-dev of x-position from start to apex.
        let tossXs = xs.prefix(apexIndex + 1).map { CGFloat($0) }
        let tossStability = 1.0 - min(1.0, standardDeviation(Array(tossXs)) * 10)

        // Eye-on-ball: fraction of the toss duration (frame 0 → apex) where
        // the ball was detected. Uses total-frames denominator, not detected-frames.
        let tossFrameCount = Double(apexIndex + 1)
        let detectedInToss = Double(min(observations.count, apexIndex + 1))
        let eyeOnBall = tossFrameCount > 0 ? detectedInToss / tossFrameCount : 0

        // Post-contact observations for serve-type guess.
        let withVelocities = velocities(from: observations)
        let postContactVels = withVelocities.dropFirst(apexIndex).compactMap(\.velocity)
        let serveTypeGuess = classifyServeType(from: postContactVels)

        let contactIdx = min(apexIndex + 3, observations.count - 1)

        return ServeMetrics(
            tossApexNormalizedX: xs[apexIndex],
            tossApexNormalizedY: ys[apexIndex],
            tossInFrameStability: tossStability,
            lateralDrift: xs[apexIndex] - (xs.first ?? xs[apexIndex]),
            eyeOnBallFraction: eyeOnBall,
            contactNormalizedX: xs[contactIdx],
            contactNormalizedY: ys[contactIdx],
            serveTypeGuess: serveTypeGuess,
            trackingQuality: TrackingQuality(detectedFrames: observations.count, totalFrames: totalFrames)
        )
    }

    private static func classifyServeType(from velocities: [CGVector]) -> ServeTypeGuess {
        guard velocities.count >= 3 else { return .unknown }
        let avgDy = velocities.map(\.dy).reduce(0, +) / Double(velocities.count)
        let avgDx = velocities.map(\.dx).reduce(0, +) / Double(velocities.count)
        let lateralRatio = abs(avgDx) / max(0.001, abs(avgDy))
        if lateralRatio > 0.6 { return .sliceLike }
        if avgDy < -0.02 { return .kickLike }
        return .flatLike
    }

    private static func standardDeviation(_ values: [CGFloat]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / CGFloat(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / CGFloat(values.count)
        return Double(sqrt(variance))
    }
}
