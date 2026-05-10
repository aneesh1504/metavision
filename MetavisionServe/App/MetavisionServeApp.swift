import SwiftUI
import MWDATCore

@main
struct MetavisionServeApp: App {
    @StateObject private var sessionManager: HSTNSessionManager
    @StateObject private var practiceStore: PracticeStore

    init() {
        do {
            try Wearables.configure()
        } catch {
            print("Wearables configure failed: \(error)")
        }

        _sessionManager = StateObject(wrappedValue: HSTNSessionManager())
        _practiceStore = StateObject(wrappedValue: PracticeStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(practiceStore)
                .onOpenURL { url in
                    Task {
                        try? await sessionManager.handleUrl(url)
                    }
                }
        }
    }
}
