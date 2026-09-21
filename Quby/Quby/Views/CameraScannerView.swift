import SwiftUI
import SwiftData

struct CameraScannerView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var viewModel = ScannerViewModel()
    @State private var focusPoint: CGPoint?
    @State private var copyMessage: String?

    private let clipboard = Clipboard()
    private let generator = QRCodeGenerator()

    private var isPresentedInWindow: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
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

            VStack {
                Spacer(minLength: 0)
                scanOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Scan from camera")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(usesDarkToolbar ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    closeScanner()
                }
            }

            if viewModel.hasTorch {
                ToolbarItem(placement: .topBarLeading) {
                    flashToolbarButton
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    copyMessage = nil
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
            openURL(url)
            viewModel.autoOpenHandled()
        }
        .onChange(of: viewModel.lastScan?.value) { _, _ in
            copyMessage = nil
        }
        .sheet(isPresented: $viewModel.isShowingDetails, onDismiss: viewModel.detailsDismissed) {
            if let scan = viewModel.lastScan {
                CodeDetailSheet(record: scan) { viewModel.isShowingDetails = false }
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func closeScanner() {
        viewModel.stop()
        if isPresentedInWindow {
            dismissWindow(id: QubyWindowID.cameraScanner)
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        switch viewModel.status {
        case .scanning:
            if let frame = viewModel.previewFrame {
                frame
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder("Starting camera…", icon: "camera")
            }

        case .idle:
            placeholder("Starting camera…", icon: "camera")

        case .denied:
            ZStack {
                Color.gray.opacity(0.2)
                VStack(spacing: 12) {
                    Image(systemName: "camera.badge.ellipsis")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Quby cannot use the camera.\nYou can turn it on in Settings.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: "app-settings:") {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

        case .unavailable:
            placeholder("No camera here.\nRun on a real device, or scan from a photo.", icon: "iphone.slash")
        }
    }

    @ViewBuilder
    private var scanOverlay: some View {
        if let scan = viewModel.lastScan {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ScannedResultPanel(
                    scan: scan,
                    copyTitle: copyButtonTitle(for: scan),
                    onViewDetails: { viewModel.isShowingDetails = true },
                    onCopy: { copy(scan) }
                )
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        } else if let message = viewModel.message {
            Text(message)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        } else if let scanHint {
            Text(scanHint)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        }
    }

    private func copyButtonTitle(for scan: CodeRecord) -> String {
        if let copyMessage { return copyMessage }
        return scan.symbology.lowercased().contains("qr") ? "Copy QR code" : "Copy barcode"
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

    private func copy(_ record: CodeRecord) {
        if record.symbology.lowercased().contains("qr"),
           let image = generator.makeImage(from: record.value) {
            clipboard.copy(image: image)
            TransientMessage.present($copyMessage, text: "QR code copied")
        } else {
            clipboard.copy(text: record.value)
            TransientMessage.present($copyMessage, text: "Barcode number copied")
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
    let copyTitle: String
    let onViewDetails: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(scan.symbology)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(scan.value)
                .font(.callout)
                .lineLimit(2)

            HStack(spacing: 8) {
                ScanCapsuleButton(title: "View details", action: onViewDetails)
                ScanCapsuleButton(title: copyTitle, action: onCopy)
            }
            .padding(.top, 4)
            .animation(.snappy, value: copyTitle)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

#Preview("Camera") {
    NavigationStack {
        CameraScannerView()
    }
    .modelContainer(for: CodeRecord.self, inMemory: true)
}
