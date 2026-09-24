import SwiftUI
import SwiftData

enum QubyWindowID {
    static let cameraScanner = "camera-scanner"
}

@main
struct QubyApp: App {

    init() {
        SettingsKey.registerDefaults()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CodeRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)

        WindowGroup(id: QubyWindowID.cameraScanner) {
            NavigationStack {
                CameraScannerView()
                    #if os(macOS)
                    .frame(minWidth: 420, idealWidth: 480, minHeight: 560, idealHeight: 680)
                    #endif
            }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 480, height: 680)
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif
    }
}
