import SwiftUI
import Combine

/// Orchestrates the serve-detection loop, voice prompts, ASR, and batch triggers.
/// Lives as a @StateObject inside SessionView.
@MainActor
final class ServeSessionController: ObservableObject {

    @Published var isDetecting = false
    @Published var confirmedCount = 0
    @Published var pendingConfirm: ServeDetectionEvent?
    @Published var showBatchPrompt = false

    private var sessionManager: HSTNSessionManager?
    private var practiceStore: PracticeStore?
    private var detector: ServeDetector?
    private var tutor = TutorVoice()
    private var asr = ServeASR()
    private var cancellables = Set<AnyCancellable>()
    private var asrFailureCount = 0
    private var lastOutcome: ServeOutcome = .unknown
    private var isAwaitingLabel = false

    private let batchThreshold = 5

    // MARK: - Lifecycle

    func attach(to manager: HSTNSessionManager, store: PracticeStore) {
        sessionManager = manager
        practiceStore = store
        confirmedCount = store.confirmedSamples.count
        pendingConfirm = nil
        showBatchPrompt = false
        let det = ServeDetector(clipBuffer: manager.clipBuffer)
        detector = det

        // Forward each incoming frame to the serve detector.
        manager.$latestImage
            .compactMap { $0 }
            .sink { [weak self] image in
                Task { @MainActor [weak self] in
                    self?.detector?.feed(image)
                }
            }
            .store(in: &cancellables)

        det.serveDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleServeDetected(event)
            }
            .store(in: &cancellables)
    }

    func detach() {
        stop()
        cancellables.removeAll()
    }

    func start() {
        guard !isDetecting else { return }
        isDetecting = true
        detector?.startWatching()
        tutor.speak(.ready)
    }

    func stop() {
        isDetecting = false
        detector?.stopWatching()
        asr.stopListening()
    }

    // MARK: - Serve event handling

    private func handleServeDetected(_ event: ServeDetector.ServeEvent) {
        guard !isAwaitingLabel else { return } // ignore while confirming a prior serve
        isAwaitingLabel = true

        // Extract metrics on a background thread.
        Task {
            let metrics = await Task.detached(priority: .userInitiated) {
                ServeMetricsExtractor.extract(from: event.frames)
            }.value

            let detection = ServeDetectionEvent(
                detectorEvent: event,
                metrics: metrics,
                suggestedServeNumber: self.inferServeNumber(),
                suggestedOutcome: .unknown
            )
            await self.beginLabelingLoop(detection)
        }
    }

    private func beginLabelingLoop(_ event: ServeDetectionEvent) async {
        asrFailureCount = 0
        guard await asr.requestAuthorization() else {
            fallbackToCard(event: event)
            return
        }

        // Ask "in or out?" via voice.
        await withCheckedContinuation { cont in
            tutor.speak(.askInOrOut) { cont.resume() }
        }

        await listenForOutcome(event: event)
    }

    private func listenForOutcome(event: ServeDetectionEvent) async {
        await withCheckedContinuation { cont in
            asr.listenOnce { [weak self] label in
                Task { @MainActor [weak self] in
                    guard let self else { cont.resume(); return }
                    switch label {
                    case .inPlay:
                        self.lastOutcome = .inPlay
                        await self.listenForServeNumber(event: event)
                        cont.resume()
                    case .faultLong, .faultWide, .faultNet:
                        self.lastOutcome = self.outcomeFrom(label)
                        self.tutor.speak(.confirmLabel)
                        self.finishLabeling(event: event, outcome: self.lastOutcome, serveNumber: self.inferServeNumber())
                        cont.resume()
                    case .unknown:
                        self.asrFailureCount += 1
                        if self.asrFailureCount >= 2 {
                            self.fallbackToCard(event: event)
                            cont.resume()
                        } else {
                            self.tutor.speak(.sorryRepeat)
                            await self.listenForOutcome(event: event)
                            cont.resume()
                        }
                    default:
                        cont.resume()
                    }
                }
            }
        }
    }

    private func listenForServeNumber(event: ServeDetectionEvent) async {
        await withCheckedContinuation { cont in
            tutor.speak(.askServeNumber) { cont.resume() }
        }

        await withCheckedContinuation { cont in
            asr.listenOnce { [weak self] label in
                Task { @MainActor [weak self] in
                    guard let self else { cont.resume(); return }
                    let number: ServeNumber
                    switch label {
                    case .firstServe: number = .first
                    case .secondServe: number = .second
                    default: number = self.inferServeNumber()
                    }
                    self.tutor.speak(.confirmLabel)
                    self.finishLabeling(event: event, outcome: .inPlay, serveNumber: number)
                    cont.resume()
                }
            }
        }
    }

    private func finishLabeling(event: ServeDetectionEvent, outcome: ServeOutcome, serveNumber: ServeNumber) {
        isAwaitingLabel = false
        guard let store = practiceStore else { return }
        recordSample(
            event: event,
            outcome: outcome,
            serveNumber: serveNumber,
            labelSource: .userVoice,
            in: store
        )
    }

    private func recordSample(
        event: ServeDetectionEvent,
        outcome: ServeOutcome,
        serveNumber: ServeNumber,
        labelSource: ServeSample.LabelSource,
        in store: PracticeStore
    ) {
        let sample = ServeSample(
            id: UUID(),
            sessionID: store.sessionID,
            timestamp: event.detectorEvent.detectedAt,
            serveNumber: serveNumber,
            outcome: outcome,
            metrics: event.metrics,
            apexFrameFilename: nil,
            contactFrameFilename: nil,
            labelSource: labelSource
        )
        store.addSample(sample)
        confirmedCount += 1
        checkBatchThreshold()
    }

    private func fallbackToCard(event: ServeDetectionEvent) {
        isAwaitingLabel = false
        pendingConfirm = event
    }

    func confirmSample(event: ServeDetectionEvent, serveNumber: ServeNumber, outcome: ServeOutcome, in store: PracticeStore) {
        recordSample(
            event: event,
            outcome: outcome,
            serveNumber: serveNumber,
            labelSource: .userTap,
            in: store
        )
        pendingConfirm = nil
        isAwaitingLabel = false
    }

    // MARK: - Batch

    private func checkBatchThreshold() {
        if confirmedCount > 0 && confirmedCount % batchThreshold == 0 {
            showBatchPrompt = true
        }
    }

    func generateReport(for store: PracticeStore) {
        let confirmed = store.confirmedSamples
        guard !confirmed.isEmpty else { return }
        let report = FeedbackEngine.generateReport(
            samples: confirmed,
            sessionID: store.sessionID,
            screenshotFilenames: []
        )
        store.addReport(report)
    }

    // MARK: - Helpers

    private func inferServeNumber() -> ServeNumber {
        guard let store = practiceStore else { return .first }
        let recent = store.samples.suffix(2)
        if recent.last?.outcome.isFault == true { return .second }
        return .first
    }

    private func outcomeFrom(_ label: ServeASR.RecognizedLabel) -> ServeOutcome {
        switch label {
        case .faultLong: return .fault_long
        case .faultWide: return .fault_wide
        case .faultNet: return .fault_net
        default: return .unknown
        }
    }
}

/// Transient struct bridging a ServeDetector.ServeEvent to the UI/labeling flow.
struct ServeDetectionEvent: Identifiable {
    let id = UUID()
    let detectorEvent: ServeDetector.ServeEvent
    let metrics: ServeMetrics
    let suggestedServeNumber: ServeNumber
    let suggestedOutcome: ServeOutcome
}
