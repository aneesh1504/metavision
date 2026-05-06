import UIKit
import Vision

struct BallObservation {
    let normalizedX: CGFloat   // 0 = left, 1 = right
    let normalizedY: CGFloat   // 0 = top, 1 = bottom (UIKit convention)
    let confidence: Float
}

/// Finds the tennis ball in a single frame using a rectangle + size heuristic.
/// Synchronous — callers control the thread. Phase 3 will upgrade the detection
/// strategy to VNDetectTrajectoriesRequest over a sliding window.
struct BallTracker {

    /// Returns the best ball candidate found in `image`, or nil if none detected.
    /// Must be called on a background thread for sequences; safe to call anywhere.
    func detect(in image: UIImage) -> BallObservation? {
        guard let cgImage = image.cgImage else { return nil }
        var result: BallObservation?
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNDetectRectanglesRequest { req, _ in
            defer { semaphore.signal() }
            guard let results = req.results as? [VNRectangleObservation] else { return }
            // Tennis ball is roughly circular; filter by aspect ratio.
            if let best = results.first(where: { obs in
                let a = obs.boundingBox.width / obs.boundingBox.height
                return a > 0.65 && a < 1.55 && obs.confidence > 0.3
            }) {
                let cx = best.boundingBox.midX
                let cy = 1.0 - best.boundingBox.midY  // flip Vision y to UIKit
                result = BallObservation(normalizedX: cx, normalizedY: cy, confidence: best.confidence)
            }
        }
        request.minimumSize = 0.01
        request.maximumObservations = 5

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        semaphore.wait()
        return result
    }
}

/// Computes per-frame velocities from a sequence of ball observations.
/// Returns (observation, velocity) pairs; velocity is nil for the first frame.
func velocities(from observations: [(obs: BallObservation, ts: Date)]) -> [(obs: BallObservation, velocity: CGVector?)] {
    observations.enumerated().map { i, pair in
        guard i > 0 else { return (pair.obs, nil) }
        let prev = observations[i - 1].obs
        let v = CGVector(dx: pair.obs.normalizedX - prev.normalizedX,
                         dy: pair.obs.normalizedY - prev.normalizedY)
        return (pair.obs, v)
    }
}
