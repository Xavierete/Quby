import SwiftUI
import PhotosUI
import SwiftData

struct GeneratorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var viewModel = GeneratorViewModel()
    @State private var photoScanner = ScannerViewModel()
    @State private var activeCreationType: QRType?
    @State private var showPhotoPicker = false
    @State private var scanPhotoItem: PhotosPickerItem?
    #if os(iOS)
    @State private var showCameraScanner = false
    #endif
    @State private var photoScanRecord: CodeRecord?
    @State private var createdDetailRecord: CodeRecord?
    @State private var browserLink: BrowserLink?
    @State private var showOfflineAlert = false
    @State private var photoScanError: String?
    @State private var showPhotoScanError = false
    @State private var photoScanCount = 0
    @State private var contentWidth: CGFloat = 0

    private let gridSpacing: CGFloat = 12
    private let resultID = "qrResult"

    private var typeColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
    }

    private var typeCardMetrics: TypeCardMetrics {
        TypeCardMetrics(containerWidth: contentWidth,
                        spacing: gridSpacing,
                        isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { proxyGeometry in
                ScrollView {
                    VStack(spacing: 24) {
                        typeButtons

                        if viewModel.activeImage != nil {
                            result
                                .id(resultID)
                        } else {
                            Spacer(minLength: 24)

                            emptyResult
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 28)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: proxyGeometry.size.height, alignment: .top)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.width
                    } action: { width in
                        contentWidth = width
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.activeImage != nil) { _, hasImage in
                guard hasImage else { return }
                scrollToResult(using: proxy)
            }
        }
        .navigationTitle("Create")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: PlatformToolbar.trailing) {
                Menu {
                    Button {
                        openCameraScanner()
                    } label: {
                        Label("Scan from camera", systemImage: "camera")
                    }
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Scan from photo", systemImage: "photo")
                    }
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                }
            }
        }
        .sheet(item: $activeCreationType, onDismiss: presentCreatedFollowUpIfNeeded) { type in
            QRCreationSheet(type: type, viewModel: viewModel)
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
                .presentationSizing(.form)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $scanPhotoItem, matching: .images)
        .sheet(item: $photoScanRecord) { record in
            CodeDetailSheet(record: record, animateContentReveal: true) { photoScanRecord = nil }
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
        }
        .sheet(item: $createdDetailRecord) { record in
            CodeDetailSheet(record: record) { createdDetailRecord = nil }
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
        }
        .sheet(item: $browserLink) { link in
            WebBrowserSheet(url: link.url) { browserLink = nil }
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showCameraScanner) {
            NavigationStack {
                CameraScannerView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        #endif
        .alert("Could not scan photo", isPresented: $showPhotoScanError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(photoScanError ?? "Try another image.")
        }
        .alert("No connection", isPresented: $showOfflineAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check your internet connection and try again.")
        }
        .sensoryFeedback(.success, trigger: photoScanCount)
        .task {
            viewModel.modelContext = modelContext
            photoScanner.modelContext = modelContext
        }
        .onChange(of: scanPhotoItem) { _, newItem in
            Task { await handlePhotoScan(newItem) }
        }
    }

    private func presentCreatedFollowUpIfNeeded() {
        if let url = viewModel.pendingWebsiteURL {
            viewModel.pendingWebsiteURL = nil
            Task {
                await InAppBrowser.open(url, into: $browserLink, offlineAlert: $showOfflineAlert)
            }
            return
        }

        guard let record = viewModel.pendingDetailRecord else { return }
        viewModel.pendingDetailRecord = nil
        createdDetailRecord = record
    }

    private func handlePhotoScan(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        let outcome = await photoScanner.scanPhoto(item)
        scanPhotoItem = nil

        switch outcome {
        case .success(let record):
            if SettingsKey.isOn(SettingsKey.scanHaptics) {
                photoScanCount += 1
            }
            photoScanRecord = record
        case .openURL(let url):
            await InAppBrowser.open(url, into: $browserLink, offlineAlert: $showOfflineAlert)
        case .failure(let message):
            photoScanError = message
            showPhotoScanError = true
        case .cancelled:
            break
        }
    }

    private func openCameraScanner() {
        #if os(macOS)
        openWindow(id: QubyWindowID.cameraScanner)
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac {
            openWindow(id: QubyWindowID.cameraScanner)
        } else {
            showCameraScanner = true
        }
        #endif
    }

    private var typeButtons: some View {
        let metrics = typeCardMetrics

        return LazyVGrid(columns: typeColumns, spacing: gridSpacing) {
            ForEach(QRType.allCases) { type in
                Button {
                    viewModel.type = type
                    activeCreationType = type
                } label: {
                    VStack(spacing: metrics.contentSpacing) {
                        Image(systemName: type.icon)
                            .font(metrics.iconFont)
                        Text(type.title)
                            .font(metrics.titleFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.cardHeight)
                    .background(typeGradient(for: type).gradient,
                                in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func typeGradient(for type: QRType) -> Color {
        switch type {
        case .website: return .blue
        case .contact: return .purple
        case .wifi: return .cyan
        case .email: return .orange
        case .sms: return .green
        case .location: return .pink
        }
    }

    private var result: some View {
        VStack(spacing: 20) {
            resultContent

            if let message = viewModel.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyResult: some View {
        VStack(spacing: 12) {
            ContentUnavailableView("No code yet",
                                   systemImage: "qrcode",
                                   description: Text("Choose a type above to get started."))

            if let message = viewModel.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if viewModel.activeImage != nil {
            let previewSide: CGFloat = horizontalSizeClass == .regular ? 320 : 260

            VStack(spacing: 12) {
                QRPreviewPager(
                    pages: viewModel.visiblePreviewPages,
                    selection: $viewModel.selectedPreviewPage,
                    side: previewSide,
                    image: previewImage(for:)
                )

                HStack(spacing: 12) {
                    Menu {
                        if let pngURL = viewModel.activePNGURL {
                            ShareLink(item: pngURL) {
                                Label("PNG image", systemImage: "photo")
                            }
                        }
                        if let pdfURL = viewModel.activePDFURL {
                            ShareLink(item: pdfURL) {
                                Label("PDF document", systemImage: "doc.text")
                            }
                        }
                        if let svgURL = viewModel.activeSVGURL {
                            ShareLink(item: svgURL) {
                                Label("SVG vector", systemImage: "curlybraces")
                            }
                        }
                    } label: {
                        resultCapsuleLabel("Share", systemImage: "square.and.arrow.up", color: .green)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.saveToPhotos() }
                    } label: {
                        Label {
                            Text(viewModel.isSavedToPhotos ? "Saved" : "Save")
                                .contentTransition(.numericText())
                        } icon: {
                            Image(systemName: viewModel.isSavedToPhotos
                                  ? "photo.badge.checkmark.fill"
                                  : "photo.badge.arrow.down.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Color.cyan.gradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.snappy, value: viewModel.isSavedToPhotos)

                    Button {
                        guard let record = viewModel.lastRecord else { return }
                        createdDetailRecord = record
                    } label: {
                        resultCapsuleLabel("More", systemImage: "info.circle.fill", color: .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.lastRecord == nil)
                }
                .lineLimit(1)
            }
        }
    }

    private func previewImage(for page: QRPreviewPage) -> Image {
        switch page {
        case .styled:
            return viewModel.styledImage ?? viewModel.baseImage ?? Image(systemName: "qrcode")
        case .base:
            return viewModel.baseImage ?? Image(systemName: "qrcode")
        }
    }

    private func resultCapsuleLabel(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(color.gradient, in: Capsule())
    }

    private func scrollToResult(using proxy: ScrollViewProxy) {
        guard viewModel.activeImage != nil else { return }

        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.smooth(duration: 0.6)) {
                proxy.scrollTo(resultID, anchor: .center)
            }
        }
    }
}

private struct TypeCardMetrics {
    let containerWidth: CGFloat
    let spacing: CGFloat
    let isRegularWidth: Bool

    private var cardSide: CGFloat {
        guard containerWidth > 0 else { return isRegularWidth ? 140 : 108 }
        let side = (containerWidth - spacing * 2) / 3
        return max(96, side)
    }

    var cardHeight: CGFloat {
        if isRegularWidth {
            return max(120, min(cardSide * 0.78, 168))
        }
        return max(96, min(cardSide * 0.92, 128))
    }

    var contentSpacing: CGFloat {
        isRegularWidth ? 12 : 8
    }

    var cornerRadius: CGFloat { 26 }

    var iconFont: Font {
        if isRegularWidth || cardSide >= 140 {
            return .largeTitle.weight(.medium)
        }
        if cardSide >= 118 {
            return .title.weight(.medium)
        }
        return .title2.weight(.medium)
    }

    var titleFont: Font {
        if isRegularWidth || cardSide >= 140 {
            return .body.weight(.semibold)
        }
        if cardSide >= 118 {
            return .callout.weight(.semibold)
        }
        return .caption.weight(.semibold)
    }
}

#Preview {
    NavigationStack {
        GeneratorView()
    }
    .modelContainer(for: CodeRecord.self, inMemory: true)
}
