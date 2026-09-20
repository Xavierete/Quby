import SwiftUI
import SwiftData

struct ContentView: View {

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
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: CodeRecord.self, inMemory: true)
}
