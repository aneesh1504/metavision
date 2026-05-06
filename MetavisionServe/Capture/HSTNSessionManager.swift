import SwiftUI
import MWDATCore
import MWDATCamera

/// Manages the lifecycle of a single HSTN streaming session.
/// All state mutations happen on MainActor; frames are forwarded to ServeClipBuffer off-main.
@MainActor
final class HSTNSessionManager: ObservableObject {

    // MARK: - State

    enum StreamState: Equatable {
        case disconnected
        case connecting
        case streaming
        case error(String)

        static func == (lhs: StreamState, rhs: StreamState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected), (.connecting, .connecting), (.streaming, .streaming):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }

        var isActive: Bool { self == .streaming }
    }

    @Published var state: StreamState = .disconnected
    @Published var latestImage: UIImage?

    // MARK: - Internal

    private var streamSession: StreamSession?
    let clipBuffer = ServeClipBuffer(capacity: 150) // ~6 s at 24 fps

    // MARK: - SDK entry points

    func handleUrl(_ url: URL) async throws {
        _ = try await Wearables.shared.handleUrl(url)
    }

    func startRegistration() throws {
        try Wearables.shared.startRegistration()
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard state == .disconnected else { return }
        state = .connecting
        do {
            let permission = try await Wearables.shared.requestPermission(.camera)
            guard permission == .authorized else {
                state = .error("Camera permission denied — grant access in Settings.")
                return
            }
            let config = StreamSessionConfig(
                videoCodec: .hvc1,
                resolution: .medium,
                frameRate: 24
            )
            let selector = AutoDeviceSelector(wearables: Wearables.shared)
            let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
            streamSession = session
            await session.start()
            state = .streaming
            session.videoFramePublisher.listen { [weak self] frame in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let image = frame.makeUIImage()
                    self.latestImage = image
                    self.clipBuffer.push(image)
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func disconnect() async {
        await streamSession?.stop()
        streamSession = nil
        state = .disconnected
    }
}
