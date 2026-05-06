import AVFoundation

/// Speaks coaching prompts through the phone's audio output (speaker or AirPods/BT if connected).
/// The HSTN SDK does not expose speaker output in v0.6, so all TTS is phone-side.
@MainActor
final class TutorVoice: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Scripted lines

    enum Line {
        case calibrationStart
        case calibrationLookStraight
        case calibrationLookDeuce
        case calibrationLookAd
        case ready
        case serveDetected
        case askInOrOut
        case askFaultZone
        case askServeNumber
        case confirmLabel
        case sorryRepeat
        case batchReadyFiveServes
        case batchReadyTenServes
        case sessionEnded
        case custom(String)

        var text: String {
            switch self {
            case .calibrationStart:
                return "Let's calibrate. Stand at the baseline and look straight ahead at the back fence."
            case .calibrationLookStraight:
                return "Hold still for three seconds."
            case .calibrationLookDeuce:
                return "Now look at the deuce service box corner."
            case .calibrationLookAd:
                return "Now the ad corner. Calibration complete — ready to serve."
            case .ready:
                return "Ready. Serve when you want."
            case .serveDetected:
                return ""   // silent — just a soft audio cue handled separately
            case .askInOrOut:
                return "Was that in or out?"
            case .askFaultZone:
                return "Where did it go — long, wide, or net?"
            case .askServeNumber:
                return "First or second serve?"
            case .confirmLabel:
                return "Got it."
            case .sorryRepeat:
                return "Sorry, I missed that — in or out?"
            case .batchReadyFiveServes:
                return "That's five. Want a quick read, or keep going?"
            case .batchReadyTenServes:
                return "That's ten. Here's your read."
            case .sessionEnded:
                return "Session ended. Check your report on screen."
            case .custom(let text):
                return text
            }
        }
    }

    func speak(_ line: Line, completion: (() -> Void)? = nil) {
        guard !line.text.isEmpty else {
            completion?()
            return
        }
        completionHandler = completion
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.completionHandler?()
            self?.completionHandler = nil
        }
    }
}
