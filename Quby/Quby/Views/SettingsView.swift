import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [CodeRecord]

    @AppStorage(SettingsKey.scanSound) private var scanSound = true
    @AppStorage(SettingsKey.scanHaptics) private var scanHaptics = true
    @AppStorage(SettingsKey.showDetailsAutomatically) private var showDetailsAutomatically = false
    @AppStorage(SettingsKey.openWebsitesAutomatically) private var openWebsitesAutomatically = false
    @AppStorage(SettingsKey.saveHistory) private var saveHistory = true
    @AppStorage(SettingsKey.saveCameraScans) private var saveCameraScans = true
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
        #if os(macOS)
        return "Only one of these can be on at a time. Codes stay quiet until you open More or View details."
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
            ? "Only one of these can be on at a time. Codes stay quiet until you open More or View details."
            : "Only one of these can be on at a time. Codes stay quiet until you tap More or View details."
        #endif
    }

    private var historyFooter: Text {
        if records.isEmpty {
            Text("Nothing saved yet. Save camera scans keeps live camera reads. Save codes keeps created codes and photo scans.")
        } else {
            Text("^[\(records.count) code](inflect: true) saved on this device. Save camera scans keeps live camera reads. Save codes keeps created codes and photo scans.")
        }
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
        NavigationStack {
            Form {
                aboutHeaderSection
                feedbackSection
                afterScanSection
                historySection
                aboutActionsSection
            }
            .formStyle(.grouped)
            .scenePadding()
            .navigationTitle("Settings")
            .sheet(isPresented: $showGuide) {
                GuideView()
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
    }

    private var aboutHeaderSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Quby")
                        .font(.title2.weight(.semibold))
                    Text("Version \(version)")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private var aboutActionsSection: some View {
        Section {
            Button {
                showGuide = true
            } label: {
                Label("Onboarding", systemImage: "hand.palm.facing")
            }
        } footer: {
            Text("Quby keeps everything on your device. Nothing is collected or sent anywhere.")
        }
    }
    #endif

    #if !os(macOS)
    private var iosBody: some View {
        NavigationStack {
            Form {
                feedbackSection
                afterScanSection
                historySection
                aboutSection
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
    }

    private var aboutSection: some View {
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
    #endif

    private var feedbackSection: some View {
        Section {
            Toggle(isOn: $scanSound) {
                Label("Sound", systemImage: "speaker.wave.2")
            }
            #if os(iOS)
            if !ProcessInfo.processInfo.isiOSAppOnMac {
                Toggle(isOn: $scanHaptics) {
                    Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                }
            }
            #endif
        } header: {
            Text("Feedback")
        } footer: {
            #if os(macOS)
            Text("Play a sound when a code is read.")
            #else
            Text(ProcessInfo.processInfo.isiOSAppOnMac
                 ? "Play a sound when a code is read."
                 : "Play a sound or vibrate when a code is read.")
            #endif
        }
    }

    private var afterScanSection: some View {
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
    }

    private var historySection: some View {
        Section {
            Toggle(isOn: $saveCameraScans) {
                Label("Save camera scans", systemImage: "camera")
            }
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
            historyFooter
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
