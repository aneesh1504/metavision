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

    private var deviceSession: DeviceSession?
    private var streamSession: StreamSession?
    private var videoFrameToken: (any AnyListenerToken)?
    let clipBuffer = ServeClipBuffer(capacity: 150) // ~6 s at 24 fps

    // MARK: - SDK entry points

    func handleUrl(_ url: URL) async throws {
        _ = try await Wearables.shared.handleUrl(url)
    }

    func startRegistration() async throws {
        try await Wearables.shared.startRegistration()
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard state == .disconnected else { return }
        state = .connecting
        do {
            // Ensure the app is registered with Meta AI before requesting
            // permissions or creating a device session. Without this the
            // SDK has no account↔app binding and returns "no device config".
            if Wearables.shared.registrationState != .registered {
                try await Wearables.shared.startRegistration()
            }

            let permission = try await Wearables.shared.requestPermission(.camera)
            guard permission == .granted else {
                state = .error("Camera permission denied — grant access in Settings.")
                return
            }

            let selector = AutoDeviceSelector(wearables: Wearables.shared)
            let device = try Wearables.shared.createSession(deviceSelector: selector)
            deviceSession = device

            let config = StreamSessionConfig(
                videoCodec: .hvc1,
                resolution: .medium,
                frameRate: 24
            )
            guard let stream = try device.addStream(config: config) else {
                state = .error("Unable to add camera stream to device session.")
                return
            }
            streamSession = stream

            videoFrameToken = stream.videoFramePublisher.listen { [weak self] frame in
                guard let image = frame.makeUIImage() else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestImage = image
                    self.clipBuffer.push(image)
                }
            }

            try device.start()
            await stream.start()
            state = .streaming
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func disconnect() async {
        await videoFrameToken?.cancel()
        videoFrameToken = nil
        await streamSession?.stop()
        streamSession = nil
        deviceSession?.stop()
        deviceSession = nil
        state = .disconnected
    }
}
