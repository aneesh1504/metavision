import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: HSTNSessionManager
    @EnvironmentObject var practiceStore: PracticeStore

    var body: some View {
        TabView {
            SessionView()
                .tabItem {
                    Label("Serve", systemImage: "sportscourt.fill")
                }
            BatchReportView()
                .tabItem {
                    Label("Reports", systemImage: "chart.bar.fill")
                }
        }
        .tint(.green)
    }
}
