import SwiftUI
import Combine

/// Main practice screen. Shows the HSTN live preview and manages the serve-detection loop.
struct SessionView: View {
    @EnvironmentObject var sessionManager: HSTNSessionManager
    @EnvironmentObject var practiceStore: PracticeStore
    @StateObject private var sessionController = ServeSessionController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Live preview
                LivePreview(image: sessionManager.latestImage)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(9/16, contentMode: .fit)
                    .overlay(alignment: .topLeading) { statusBadge }
                    .overlay(alignment: .bottom) { serveCountBadge }

                // Controls
                controlBar
            }
        }
        .sheet(item: $sessionController.pendingConfirm) { event in
            ServeConfirmCard(event: event) { serveNumber, outcome in
                sessionController.confirmSample(
                    event: event,
                    serveNumber: serveNumber,
                    outcome: outcome,
                    in: practiceStore
                )
            }
        }
        .alert("Batch Ready", isPresented: $sessionController.showBatchPrompt) {
            Button("See Report") { sessionController.generateReport(for: practiceStore) }
            Button("Keep Going") { }
        } message: {
            Text("You've confirmed \(sessionController.confirmedCount) serves. Want a read?")
        }
        .onAppear {
            sessionController.attach(to: sessionManager, store: practiceStore)
        }
        .onDisappear {
            sessionController.detach()
        }
    }

    // MARK: - Sub-views

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sessionManager.state == .streaming ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(12)
    }

    private var serveCountBadge: some View {
        Text("\(sessionController.confirmedCount) serves")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 12)
    }

    private var controlBar: some View {
        HStack(spacing: 20) {
            if sessionManager.state == .disconnected && !sessionManager.isRegistered {
                Button("Authorize Wearables") {
                    Task { await sessionManager.register() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else if sessionManager.state == .disconnected {
                Button("Connect Glasses") {
                    Task { await sessionManager.connect() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else if sessionManager.state == .streaming {
                Button(sessionController.isDetecting ? "Stop" : "Start Serve Practice") {
                    if sessionController.isDetecting {
                        sessionController.stop()
                    } else {
                        sessionController.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(sessionController.isDetecting ? .red : .green)
            } else if sessionManager.state == .connecting {
                ProgressView("Connecting…")
                    .tint(.white)
            }

            if case .error(let msg) = sessionManager.state {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.black)
    }

    private var statusText: String {
        switch sessionManager.state {
        case .disconnected: return "No glasses"
        case .connecting: return "Connecting…"
        case .streaming: return sessionController.isDetecting ? "Watching" : "Connected"
        case .error: return "Error"
        }
    }
}

// MARK: - Live Preview

private struct LivePreview: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color(white: 0.1))
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "glasses")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }
}
