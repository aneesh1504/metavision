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

    private var ballTracker: BallTracker?
    private let clipBuffer: ServeClipBuffer
    private var frameCount = 0
    private var state: DetectionState = .idle

    private enum DetectionState {
        case idle
        case tossInProgress(startFrame: Int)
        case postContact(startFrame: Int, contactFrame: Int)
    }

    init(clipBuffer: ServeClipBuffer) {
        self.clipBuffer = clipBuffer
        self.ballTracker = BallTracker()
    }

    // MARK: - Feed frames

    /// Call this for every incoming VideoFrame. Runs the lightweight detection heuristic.
    func feed(_ image: UIImage) {
        guard isWatching else { return }
        frameCount += 1

        // Phase 0 stub: use BallTracker to find the ball, then run the state machine.
        // Full Vision trajectory request will replace this in Phase 3.
        ballTracker?.detect(in: image) { [weak self] observation in
            guard let self else { return }
            self.advance(observation: observation, frame: image)
        }
    }

    // MARK: - State machine

    private func advance(observation: BallObservation?, frame: UIImage) {
        switch state {
        case .idle:
            // Transition to tossInProgress if ball appears in lower half moving upward.
            if let obs = observation, obs.normalizedY > 0.5, obs.velocity.dy < -0.02 {
                state = .tossInProgress(startFrame: frameCount)
            }

        case .tossInProgress(let start):
            // If ball slows significantly or reverses, we're near apex or contact.
            if let obs = observation {
                if obs.velocity.dy > 0.01 || abs(obs.velocity.dx) > 0.15 {
                    // Trajectory changed — likely contact or return downward.
                    state = .postContact(startFrame: start, contactFrame: frameCount)
                    emitEvent(startFrameOffset: frameCount - start, contactOffset: frameCount - start)
                }
            } else if frameCount - start > 72 {
                // Ball out of frame for > 3 s — reset
                state = .idle
            }

        case .postContact:
            // Reset after a short cooldown.
            if frameCount.isMultiple(of: 48) {
                state = .idle
            }
        }
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
    }

    func stopWatching() {
        isWatching = false
    }
}
