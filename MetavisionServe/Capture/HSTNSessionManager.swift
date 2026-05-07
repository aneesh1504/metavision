import SwiftUI
import MWDATCore
import MWDATCamera

/// Manages the lifecycle of a single HSTN streaming session.
/// All state mutations happen on MainActor; frames are forwarded to ServeClipBuffer off-main.
@MainActor
final class HSTNSessionManager: ObservableObject {

    // MARK: - State

    struct DeviceSnapshot: Identifiable, Equatable {
        let identifier: DeviceIdentifier
        let name: String
        let deviceType: String
        let linkState: LinkState
        let compatibility: Compatibility

        var id: DeviceIdentifier { identifier }
        var isEligible: Bool { linkState == .connected && compatibility == .compatible }

        var linkStateText: String {
            switch linkState {
            case .connected: return "connected"
            case .connecting: return "connecting"
            case .disconnected: return "disconnected"
            }
        }

        var compatibilityText: String {
            compatibility.displayString
        }

        var summaryText: String {
            "\(name): \(linkStateText), \(compatibilityText)"
        }
    }

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
    @Published var isRegistered: Bool = false
    @Published private(set) var deviceSnapshots: [DeviceSnapshot] = []

    var hasEligibleDevice: Bool {
        deviceSnapshots.contains { $0.isEligible }
    }

    var deviceAvailabilityText: String {
        guard isRegistered else { return "Authorize Wearables to discover glasses." }
        guard !deviceSnapshots.isEmpty else { return "DAT sees no glasses yet." }

        let eligibleNames = deviceSnapshots
            .filter { $0.isEligible }
            .map(\.name)
            .joined(separator: ", ")

        if !eligibleNames.isEmpty {
            return "Ready: \(eligibleNames)"
        }

        return deviceSnapshots.map(\.summaryText).joined(separator: " | ")
    }

    // MARK: - Internal

    private var deviceSession: DeviceSession?
    private var streamSession: StreamSession?
    private var videoFrameToken: (any AnyListenerToken)?
    private var registrationStateToken: (any AnyListenerToken)?
    private var devicesToken: (any AnyListenerToken)?
    private var linkStateTokens: [DeviceIdentifier: any AnyListenerToken] = [:]
    private var compatibilityTokens: [DeviceIdentifier: any AnyListenerToken] = [:]
    let clipBuffer = ServeClipBuffer(capacity: 150) // ~6 s at 24 fps

    init() {
        updateRegistrationState(Wearables.shared.registrationState)
        refreshCurrentDevices()
        registrationStateToken = Wearables.shared.addRegistrationStateListener { [weak self] registrationState in
            Task { @MainActor [weak self] in
                self?.updateRegistrationState(registrationState)
            }
        }
        devicesToken = Wearables.shared.addDevicesListener { [weak self] deviceIDs in
            Task { @MainActor [weak self] in
                self?.refreshDeviceSnapshots(for: deviceIDs)
            }
        }
    }

    // MARK: - SDK entry points

    func handleUrl(_ url: URL) async throws {
        _ = try await Wearables.shared.handleUrl(url)
        updateRegistrationState(Wearables.shared.registrationState)
    }

    func startRegistration() async throws {
        try await Wearables.shared.startRegistration()
        updateRegistrationState(Wearables.shared.registrationState)
    }

    /// Triggered by an explicit user tap so iOS preserves user-gesture
    /// trust when the SDK calls `openURL` to redirect to Meta AI. Do not
    /// chain other awaits before this.
    func register() async {
        state = .connecting
        do {
            try await Wearables.shared.startRegistration()
            updateRegistrationState(Wearables.shared.registrationState)
            state = .disconnected
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard state == .disconnected else { return }
        // Defensive: connect() should only be reachable from the UI when
        // already registered, but if the state ever drifts (e.g. user taps
        // through a stale view), no-op rather than dropping into .error,
        // which would hide the Authorize button.
        guard Wearables.shared.registrationState == .registered else { return }
        state = .connecting
        do {
            let permission = try await Wearables.shared.requestPermission(.camera)
            guard permission == .granted else {
                state = .error("Camera permission denied — grant access in Settings.")
                return
            }

            refreshCurrentDevices()
            guard let deviceID = await waitForEligibleDevice(timeoutSeconds: 8) else {
                state = .error(deviceUnavailableMessage())
                return
            }

            let selector = SpecificDeviceSelector(device: deviceID)
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

    private func updateRegistrationState(_ registrationState: RegistrationState) {
        isRegistered = (registrationState == .registered)
        refreshCurrentDevices()
        if isRegistered && state == .connecting && streamSession == nil {
            state = .disconnected
        }
    }

    private func refreshCurrentDevices() {
        refreshDeviceSnapshots(for: Wearables.shared.devices)
    }

    private func refreshDeviceSnapshots(for deviceIDs: [DeviceIdentifier]) {
        let activeIDs = Set(deviceIDs)
        pruneDeviceListeners(keeping: activeIDs)

        deviceSnapshots = deviceIDs.compactMap { identifier in
            guard let device = Wearables.shared.deviceForIdentifier(identifier) else { return nil }

            if linkStateTokens[identifier] == nil {
                linkStateTokens[identifier] = device.addLinkStateListener { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshCurrentDevices()
                    }
                }
            }

            if compatibilityTokens[identifier] == nil {
                compatibilityTokens[identifier] = device.addCompatibilityListener { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshCurrentDevices()
                    }
                }
            }

            return DeviceSnapshot(
                identifier: identifier,
                name: device.nameOrId(),
                deviceType: device.deviceType().rawValue,
                linkState: device.linkState,
                compatibility: device.compatibility()
            )
        }
    }

    private func pruneDeviceListeners(keeping activeIDs: Set<DeviceIdentifier>) {
        let staleLinkIDs = linkStateTokens.keys.filter { !activeIDs.contains($0) }
        for identifier in staleLinkIDs {
            if let token = linkStateTokens.removeValue(forKey: identifier) {
                Task { await token.cancel() }
            }
        }

        let staleCompatibilityIDs = compatibilityTokens.keys.filter { !activeIDs.contains($0) }
        for identifier in staleCompatibilityIDs {
            if let token = compatibilityTokens.removeValue(forKey: identifier) {
                Task { await token.cancel() }
            }
        }
    }

    private func waitForEligibleDevice(timeoutSeconds: Int) async -> DeviceIdentifier? {
        if let deviceID = eligibleDeviceID() { return deviceID }

        for _ in 0..<(timeoutSeconds * 2) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            refreshCurrentDevices()
            if let deviceID = eligibleDeviceID() { return deviceID }
        }

        return nil
    }

    private func eligibleDeviceID() -> DeviceIdentifier? {
        deviceSnapshots.first { $0.isEligible }?.identifier
    }

    private func deviceUnavailableMessage() -> String {
        guard !deviceSnapshots.isEmpty else {
            return "DAT sees no glasses. Open Meta AI, confirm the glasses show Connected, then try again."
        }

        if deviceSnapshots.contains(where: { $0.compatibility != .compatible }) {
            return "Glasses found but not eligible: \(deviceAvailabilityText). Update glasses firmware or Meta AI, then try again."
        }

        return "Glasses found but not connected: \(deviceAvailabilityText). Wake the glasses and confirm Meta AI shows Connected."
    }
}
