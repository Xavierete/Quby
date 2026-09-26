import SwiftUI
import SwiftData
import Photos
#if os(iOS)
import UIKit
#endif

struct CameraScannerView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var viewModel = ScannerViewModel()
    @State private var focusPoint: CGPoint?
    @State private var isSavedToPhotos = false
    @State private var saveResetTask: Task<Void, Never>?
    @State private var browserLink: BrowserLink?
    @State private var showOfflineAlert = false
    @State private var saveMessage: String?

    private let generator = QRCodeGenerator()

    private var runsOnMac: Bool {
        #if os(macOS)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                cameraArea
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        viewModel.focus(atTap: location, in: proxy.size)
                        showFocusRing(at: location)
                    }
                    .overlay {
                        if let focusPoint {
                            Circle()
                                .stroke(.yellow, lineWidth: 2)
                                .frame(width: 64, height: 64)
                                .position(focusPoint)
                        }
                    }
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            scanOverlayCard
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle("Scan from camera")
        .toolbarTitleDisplayMode(.inline)
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(usesDarkToolbar ? .dark : .light, for: .navigationBar)
        #endif
        .toolbar {
            if viewModel.hasTorch {
                ToolbarItem(placement: PlatformToolbar.leading) {
                    flashToolbarButton
                }
            }

            ToolbarItem(placement: PlatformToolbar.trailing) {
                Button {
                    isSavedToPhotos = false
                    saveResetTask?.cancel()
                    viewModel.clearResult()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(resetIconColor)
                }
                .disabled(!canResetScan)
            }
        }
        .task {
            viewModel.modelContext = modelContext
            await viewModel.start()
        }
        .onDisappear { viewModel.stop() }
        .sensoryFeedback(.success, trigger: viewModel.scanCount)
        .onChange(of: viewModel.autoOpenURL) { _, url in
            guard let url else { return }
            viewModel.autoOpenHandled()
            Task {
                await InAppBrowser.open(url, into: $browserLink, offlineAlert: $showOfflineAlert)
            }
        }
        .onChange(of: viewModel.lastScan?.value) { _, _ in
            isSavedToPhotos = false
            saveResetTask?.cancel()
            saveMessage = nil
        }
        .sheet(isPresented: $viewModel.isShowingDetails, onDismiss: viewModel.detailsDismissed) {
            if let scan = viewModel.lastScan {
                CodeDetailSheet(record: scan, animateContentReveal: true) {
                    viewModel.isShowingDetails = false
                }
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
            }
        }
        .sheet(item: $browserLink) { link in
            WebBrowserSheet(url: link.url) { browserLink = nil }
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
        }
        .alert("No connection", isPresented: $showOfflineAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check your internet connection and try again.")
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        switch viewModel.status {
        case .scanning:
            CameraPreviewView(session: viewModel.captureSession)

        case .idle:
            placeholder("Starting camera…", icon: "camera")

        case .denied:
            ZStack {
                Color.gray.opacity(0.2)
                VStack(spacing: 12) {
                    Image(systemName: "camera.badge.ellipsis")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(runsOnMac
                         ? "Quby cannot use the camera.\nAllow camera access in System Settings."
                         : "Quby cannot use the camera.\nYou can turn it on in Settings.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        openPrivacySettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

        case .unavailable:
            placeholder(
                runsOnMac
                    ? "No camera available.\nConnect a webcam or Continuity Camera, or scan from a photo."
                    : "No camera here.\nRun on a real device, or scan from a photo.",
                icon: runsOnMac ? "camera.slash" : "iphone.slash"
            )
        }
    }

    private func openPrivacySettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            openURL(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }

    private var panelCollapseSpring: Animation {
        .spring(response: 0.62, dampingFraction: 0.9)
    }

    private var overlayPhase: String {
        if viewModel.lastScan != nil { return "result" }
        if viewModel.message != nil || saveMessage != nil { return "message" }
        if scanHint != nil { return "hint" }
        return "hidden"
    }

    @ViewBuilder
    private var scanOverlayCard: some View {
        if overlayPhase != "hidden" {
            VStack(alignment: .leading, spacing: 12) {
                if let scan = viewModel.lastScan {
                    ScannedResultPanel(
                        scan: scan,
                        isSavedToPhotos: isSavedToPhotos,
                        onViewDetails: { viewModel.openDetails() },
                        onSave: { Task { await saveToPhotos(scan) } }
                    )
                    .transition(.opacity)
                } else if let message = viewModel.message ?? saveMessage {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                } else if let scanHint {
                    Text(scanHint)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .animation(panelCollapseSpring, value: overlayPhase)
            .animation(panelCollapseSpring, value: viewModel.lastScan?.value)
            .animation(panelCollapseSpring, value: isSavedToPhotos)
        }
    }

    private func saveToPhotos(_ record: CodeRecord) async {
        guard !isSavedToPhotos else { return }
        guard let image = generator.makeImage(from: record.value),
              let data = generator.pngData(from: image) else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = "Photos access denied."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            withAnimation(.snappy) {
                isSavedToPhotos = true
            }
            saveResetTask?.cancel()
            saveResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.2))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) {
                    isSavedToPhotos = false
                }
            }
        } catch {
            saveMessage = "Could not save the image."
        }
    }

    private var scanHint: String? {
        guard viewModel.lastScan == nil,
              viewModel.message == nil,
              viewModel.status != .denied,
              viewModel.status != .unavailable else { return nil }
        return "Point the camera at a QR code or barcode"
    }

    private var usesDarkToolbar: Bool {
        switch viewModel.status {
        case .scanning, .idle:
            return true
        case .denied, .unavailable:
            return false
        }
    }

    private var canResetScan: Bool {
        viewModel.lastScan != nil
    }

    private var resetIconColor: Color {
        canResetScan ? .primary : .gray
    }

    private var flashToolbarButton: some View {
        Button {
            viewModel.toggleTorch()
        } label: {
            Image(systemName: viewModel.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(viewModel.isTorchOn ? Color.yellow : Color.primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .disabled(viewModel.status != .scanning)
    }

    private func placeholder(_ message: String, icon: String) -> some View {
        ZStack {
            Color.gray.opacity(0.2)
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.largeTitle)
                Text(message)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func showFocusRing(at point: CGPoint) {
        focusPoint = point
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            if focusPoint == point { focusPoint = nil }
        }
    }
}

private struct ScannedResultPanel: View {

    let scan: CodeRecord
    let isSavedToPhotos: Bool
    let onViewDetails: () -> Void
    let onSave: () -> Void

    @State private var isValueReady = false

    var body: some View {
        VStack(spacing: 12) {
            Text(scan.symbology)
                .font(.caption)
                .foregroundStyle(.secondary)

            LoadingShimmerText(
                text: scan.value,
                isLoading: !isValueReady,
                font: .callout,
                multilineTextAlignment: .center,
                lineLimit: 2
            )

            HStack(spacing: 12) {
                Button(action: onSave) {
                    Label {
                        Text(isSavedToPhotos ? "Saved" : "Save")
                            .contentTransition(.numericText())
                    } icon: {
                        Image(systemName: isSavedToPhotos
                              ? "photo.badge.checkmark.fill"
                              : "photo.badge.arrow.down.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .font(.body.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(.white)
                    .background(Color.cyan.gradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: isSavedToPhotos)

                Button(action: onViewDetails) {
                    Label("More", systemImage: "info.circle.fill")
                        .font(.body.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundStyle(.white)
                        .background(Color.blue.gradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .lineLimit(1)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: scan.value) {
            isValueReady = false
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1450))
            withAnimation(.smooth(duration: 0.95)) {
                isValueReady = true
            }
        }
    }
}

#Preview("Camera") {
    NavigationStack {
        CameraScannerView()
    }
    .modelContainer(for: CodeRecord.self, inMemory: true)
}
