import SwiftUI
import SwiftData

struct ContentView: View {

    @AppStorage(SettingsKey.hasSeenGuide) private var hasSeenGuide = false
    @State private var showGuide = false

    var body: some View {
        TabView {
            Tab("Create", systemImage: "qrcode") {
                NavigationStack {
                    GeneratorView()
                }
            }

            Tab("History", systemImage: "clock") {
                HistoryView()
            }

            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            if !hasSeenGuide {
                showGuide = true
                hasSeenGuide = true
            }
        }
        .sheet(isPresented: $showGuide) {
            GuideView()
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
                #if os(macOS)
                .frame(minWidth: 420, idealWidth: 480, minHeight: 520)
                #endif
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: CodeRecord.self, inMemory: true)
}
