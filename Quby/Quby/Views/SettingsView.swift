import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [CodeRecord]

    @AppStorage(SettingsKey.scanSound) private var scanSound = true
    @AppStorage(SettingsKey.scanHaptics) private var scanHaptics = true
    @AppStorage(SettingsKey.showDetailsAutomatically) private var showDetailsAutomatically = false
    @AppStorage(SettingsKey.openWebsitesAutomatically) private var openWebsitesAutomatically = false
    @AppStorage(SettingsKey.saveHistory) private var saveHistory = true
    @State private var confirmClear = false
    @State private var showGuide = false

    private var version: String {
        let dictionary = Bundle.main.infoDictionary
        let short = dictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = dictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var openDetailsBinding: Binding<Bool> {
        Binding(
            get: { showDetailsAutomatically },
            set: { newValue in
                showDetailsAutomatically = newValue
                if newValue { openWebsitesAutomatically = false }
            }
        )
    }

    private var openWebsitesBinding: Binding<Bool> {
        Binding(
            get: { openWebsitesAutomatically },
            set: { newValue in
                openWebsitesAutomatically = newValue
                if newValue { showDetailsAutomatically = false }
            }
        )
    }

    private var afterScanFooter: String {
        if openWebsitesAutomatically {
            return "Open websites is on, so Open details stays off. Safe links open in Quby with WebKit; flagged ones wait for you."
        }
        if showDetailsAutomatically {
            return "Open details is on, so Open websites stays off. The details screen opens as soon as a code is created or read."
        }
        return ProcessInfo.processInfo.isiOSAppOnMac
            ? "Only one of these can be on at a time. Codes stay quiet until you open More or View details."
            : "Only one of these can be on at a time. Codes stay quiet until you tap More or View details."
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $scanSound) {
                    Label("Sound", systemImage: "speaker.wave.2")
                }
                if !ProcessInfo.processInfo.isiOSAppOnMac {
                    Toggle(isOn: $scanHaptics) {
                        Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
            } header: {
                Text("Feedback")
            } footer: {
                Text(ProcessInfo.processInfo.isiOSAppOnMac
                     ? "Play a sound when a code is read."
                     : "Play a sound or vibrate when a code is read.")
            }

            Section {
                Toggle(isOn: openDetailsBinding) {
                    Label("Open details", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Toggle(isOn: openWebsitesBinding) {
                    Label("Open websites", systemImage: "safari")
                }
            } header: {
                Text("After a code")
            } footer: {
                Text(afterScanFooter)
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
