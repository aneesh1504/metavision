import Speech
import AVFoundation

/// Listens for a single short spoken label using the iPhone microphone.
/// Constrained vocabulary for maximum accuracy on-court.
/// Note: on-device recognition requires iOS 17+. iOS 16 will use the network.
@MainActor
final class ServeASR: NSObject {

    enum RecognizedLabel {
        case inPlay
        case faultLong, faultWide, faultNet
        case firstServe, secondServe
        case readReport, keepGoing
        case unknown(String)
    }

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var listenTimer: Timer?

    private let listenWindowSeconds: TimeInterval = 5

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Listen for one label

    /// Opens a short ASR window (5 s) and calls completion with the best match.
    /// Automatically closes after `listenWindowSeconds` or on first confident result.
    func listenOnce(completion: @escaping (RecognizedLabel) -> Void) {
        stopListening()

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.recognizer = recognizer
        let engine = AVAudioEngine()
        audioEngine = engine

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        // Constrained vocabulary — dramatically improves accuracy in noisy outdoor environments.
        req.contextualStrings = [
            "in", "out",
            "long", "wide", "net",
            "first", "second",
            "read it", "keep going",
            "yes", "no"
        ]
        self.request = req

        do {
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }
            try engine.start()
        } catch {
            completion(.unknown("mic error"))
            return
        }

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString.lowercased().trimmingCharacters(in: .whitespaces)
                let label = Self.parse(text)
                if result.isFinal || Self.isConfident(label) {
                    self.stopListening()
                    completion(label)
                }
            } else if error != nil {
                self.stopListening()
                completion(.unknown("recognition error"))
            }
        }

        // Auto-close after the listen window.
        listenTimer = Timer.scheduledTimer(withTimeInterval: listenWindowSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.task != nil else { return }
                self.stopListening()
                completion(.unknown("timeout"))
            }
        }
    }

    func stopListening() {
        listenTimer?.invalidate()
        listenTimer = nil
        task?.cancel()
        task = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        request?.endAudio()
        request = nil
    }

    // MARK: - Parsing

    private static func parse(_ text: String) -> RecognizedLabel {
        if text.contains("in")  && !text.contains("wide") && !text.contains("long") && !text.contains("net") { return .inPlay }
        if text.contains("long") { return .faultLong }
        if text.contains("wide") { return .faultWide }
        if text.contains("net") { return .faultNet }
        if text.contains("first") || text.contains("one") { return .firstServe }
        if text.contains("second") || text.contains("two") { return .secondServe }
        if text.contains("read") || text.contains("report") { return .readReport }
        if text.contains("keep") || text.contains("continue") { return .keepGoing }
        return .unknown(text)
    }

    private static func isConfident(_ label: RecognizedLabel) -> Bool {
        if case .unknown = label { return false }
        return true
    }
}
