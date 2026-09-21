import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [CodeRecord]

    @AppStorage(SettingsKey.scanSound) private var scanSound = true
    @AppStorage(SettingsKey.scanHaptics) private var scanHaptics = true
    @AppStorage(SettingsKey.showDetailsAutomatically) private var showDetailsAutomatically = false
    @AppStorage(SettingsKey.saveHistory) private var saveHistory = true
    @AppStorage(SettingsKey.openWebsitesAutomatically) private var openWebsitesAutomatically = false
    @State private var confirmClear = false
    @State private var showGuide = false

    private var version: String {
        let dictionary = Bundle.main.infoDictionary
        let short = dictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = dictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $scanSound) {
                    Label("Sound", systemImage: "speaker.wave.2")
                }
                Toggle(isOn: $scanHaptics) {
                    Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                }
                Toggle(isOn: $showDetailsAutomatically) {
                    Label("Open details", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Toggle(isOn: $openWebsitesAutomatically) {
                    Label("Open websites", systemImage: "safari")
                }
            } header: {
                Text("When a code is read")
            } footer: {
                Text(openWebsitesAutomatically
                     ? "Links go straight to your browser. Anything Quby flags as risky still waits for you."
                     : (showDetailsAutomatically
                        ? "The details screen opens as soon as a code is read."
                        : "Codes are read quietly. Tap View details when you want them."))
            }

            Section {
                Toggle(isOn: $saveHistory) {
                    Label("Save codes", systemImage: "clock.arrow.circlepath")
                }

                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label {
                        Text("Clear history")
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(records.isEmpty)
            } header: {
                Text("History")
            } footer: {
                Text(records.isEmpty
                     ? "Nothing saved yet."
                     : "^[\(records.count) code](inflect: true) saved on this device.")
            }

            Section {
                Button {
                    showGuide = true
                } label: {
                    Label("Onboarding", systemImage: "hand.palm.facing")
                }

                LabeledContent("Version", value: version)
            } header: {
                Text("About")
            } footer: {
                Text("Quby keeps everything on your device. Nothing is collected or sent anywhere.")
            }
        }
        .navigationTitle("Settings")
        .toolbarTitleDisplayMode(.inlineLarge)
        .sheet(isPresented: $showGuide) {
            GuideView()
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Delete every saved code?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { clearHistory() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func clearHistory() {
        try? modelContext.delete(model: CodeRecord.self)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: CodeRecord.self, inMemory: true)
}
