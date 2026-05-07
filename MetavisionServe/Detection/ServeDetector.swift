import UIKit
import Combine

/// Watches the frame stream and emits a ServeEvent when it detects a complete serve sequence
/// (toss arc → apex → ball departure / trajectory change).
///
/// Phase 0: rule-based stub that fires after detecting upward ball motion followed by
/// a trajectory reversal or ball exit. Replace with Vision VNDetectTrajectoriesRequest in Phase 3.
@MainActor
final class ServeDetector: ObservableObject {

    struct ServeEvent {
        let frames: [(image: UIImage, timestamp: Date)]
        let detectedAt: Date
        let confidence: Float          // 0–1
        let approxContactIndex: Int?   // index into frames where contact likely occurred
    }

    // Emits each time a serve is confidently detected.
    let serveDetected = PassthroughSubject<ServeEvent, Never>()

    @Published var isWatching = false

    private let clipBuffer: ServeClipBuffer
    private let detectionQueue = DispatchQueue(label: "com.metavision.serve.detector", qos: .userInitiated)
    private var frameCount = 0
    private var isProcessingFrame = false
    private var lastObservation: (observation: BallObservation, frameNumber: Int)?
    private var state: DetectionState = .idle

    private struct TrackedObservation {
        let observation: BallObservation
        let velocity: CGVector
    }

    private enum DetectionState {
        case idle
        case tossInProgress(startFrame: Int)
        case postContact(startFrame: Int, contactFrame: Int)
    }

    init(clipBuffer: ServeClipBuffer) {
        self.clipBuffer = clipBuffer
    }

    // MARK: - Feed frames

    /// Call this for every incoming VideoFrame. Runs the lightweight detection heuristic.
    func feed(_ image: UIImage) {
        guard isWatching, !isProcessingFrame else { return }
        frameCount += 1
        let frameNumber = frameCount
        isProcessingFrame = true

        // Phase 0 stub: use BallTracker to find the ball, then run the state machine.
        // Full Vision trajectory request will replace this in Phase 3.
        detectionQueue.async {
            let observation = BallTracker().detect(in: image)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isProcessingFrame = false
                guard self.isWatching else { return }
                let tracked = self.trackedObservation(from: observation, frameNumber: frameNumber)
                self.advance(observation: tracked, frameNumber: frameNumber)
            }
        }
    }

    // MARK: - State machine

    private func advance(observation: TrackedObservation?, frameNumber: Int) {
        switch state {
        case .idle:
            // Transition to tossInProgress if ball appears in lower half moving upward.
            if let obs = observation, obs.observation.normalizedY > 0.5, obs.velocity.dy < -0.02 {
                state = .tossInProgress(startFrame: frameNumber)
            }

        case .tossInProgress(let start):
            // If ball slows significantly or reverses, we're near apex or contact.
            if let obs = observation {
                if obs.velocity.dy > 0.01 || abs(obs.velocity.dx) > 0.15 {
                    // Trajectory changed — likely contact or return downward.
                    state = .postContact(startFrame: start, contactFrame: frameNumber)
                    emitEvent(startFrameOffset: frameNumber - start, contactOffset: frameNumber - start)
                }
            } else if frameNumber - start > 72 {
                // Ball out of frame for > 3 s — reset
                state = .idle
            }

        case .postContact(_, let contact):
            // Reset after a short cooldown.
            if frameNumber - contact >= 48 {
                state = .idle
            }
        }
    }

    private func trackedObservation(from observation: BallObservation?, frameNumber: Int) -> TrackedObservation? {
        guard let observation else { return nil }
        defer {
            lastObservation = (observation, frameNumber)
        }

        guard let lastObservation else {
            return TrackedObservation(observation: observation, velocity: .zero)
        }

        let frameDelta = CGFloat(max(1, frameNumber - lastObservation.frameNumber))
        let velocity = CGVector(
            dx: (observation.normalizedX - lastObservation.observation.normalizedX) / frameDelta,
            dy: (observation.normalizedY - lastObservation.observation.normalizedY) / frameDelta
        )
        return TrackedObservation(observation: observation, velocity: velocity)
    }

    private func emitEvent(startFrameOffset: Int, contactOffset: Int) {
        let clip = clipBuffer.tail(startFrameOffset + 20)
        guard clip.count >= 5 else { return }

        let event = ServeEvent(
            frames: clip,
            detectedAt: Date(),
            confidence: 0.7,
            approxContactIndex: min(contactOffset, clip.count - 1)
        )
        serveDetected.send(event)
    }

    // MARK: - Control

    func startWatching() {
        isWatching = true
        state = .idle
        frameCount = 0
        isProcessingFrame = false
        lastObservation = nil
    }

    func stopWatching() {
        isWatching = false
        lastObservation = nil
    }
}
