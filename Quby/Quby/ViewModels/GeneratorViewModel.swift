import SwiftUI
import SwiftData
import Photos
import ImageIO

enum QRPreviewPage: Int, CaseIterable, Identifiable {
    case styled = 0
    case base = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .styled: return "Styled"
        case .base: return "Base"
        }
    }
}

@Observable
final class GeneratorViewModel {

    var type: QRType = .website {
        didSet { clearResult() }
    }
    var input = QRInput()

    var style = QRStyle() {
        didSet { redrawIfNeeded() }
    }
    private(set) var hasLogo = false

    var selectedPreviewPage: QRPreviewPage = .styled {
        didSet {
            guard selectedPreviewPage != oldValue else { return }
            saveResetTask?.cancel()
            saveResetTask = nil
            isSavedToPhotos = false
        }
    }

    private(set) var styledImage: Image?
    private(set) var baseImage: Image?
    private(set) var styledPNGURL: URL?
    private(set) var basePNGURL: URL?
    private(set) var styledPDFURL: URL?
    private(set) var basePDFURL: URL?
    private(set) var styledSVGURL: URL?
    private(set) var baseSVGURL: URL?
    private(set) var message: String?
    /// Latest created record for the current QR preview.
    private(set) var lastRecord: CodeRecord?
    private(set) var isSavedToPhotos = false
    private(set) var isGenerating = false

    /// Set when Create should open details after the creation sheet dismisses.
    var pendingDetailRecord: CodeRecord?
    /// Set when Create should open a safe website in WebKit after the sheet dismisses.
    var pendingWebsiteURL: URL?

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private let builder = QRPayloadBuilder()
    @ObservationIgnored private let persistence = CodeScanPersistence()
    @ObservationIgnored private var styledCGImage: CGImage?
    @ObservationIgnored private var baseCGImage: CGImage?
    @ObservationIgnored private var logo: CGImage?
    @ObservationIgnored private var saveResetTask: Task<Void, Never>?
    @ObservationIgnored private var generateTask: Task<Void, Never>?
    @ObservationIgnored private var generateSerial = 0

    var canGenerate: Bool {
        builder.payload(for: type, input: input) != nil
    }

    /// True when the styled render differs from the classic base.
    var showsBothPreviews: Bool {
        hasLogo || style != QRStyle()
    }

    var visiblePreviewPages: [QRPreviewPage] {
        showsBothPreviews ? QRPreviewPage.allCases : [.base]
    }

    var activeImage: Image? {
        switch resolvedSelection {
        case .styled: return styledImage ?? baseImage
        case .base: return baseImage
        }
    }

    var activePNGURL: URL? {
        switch resolvedSelection {
        case .styled: return styledPNGURL ?? basePNGURL
        case .base: return basePNGURL
        }
    }

    var activePDFURL: URL? {
        switch resolvedSelection {
        case .styled: return styledPDFURL ?? basePDFURL
        case .base: return basePDFURL
        }
    }

    var activeSVGURL: URL? {
        switch resolvedSelection {
        case .styled: return styledSVGURL ?? baseSVGURL
        case .base: return baseSVGURL
        }
    }

    private var resolvedSelection: QRPreviewPage {
        if showsBothPreviews { return selectedPreviewPage }
        return .base
    }

    private var activeCGImage: CGImage? {
        switch resolvedSelection {
        case .styled: return styledCGImage ?? baseCGImage
        case .base: return baseCGImage
        }
    }

    func generate(queueDetailsIfEnabled: Bool = false) {
        generateTask?.cancel()
        saveResetTask?.cancel()
        saveResetTask = nil
        message = nil
        isSavedToPhotos = false

        guard let payload = builder.payload(for: type, input: input) else {
            clearResult()
            message = "Fill in the fields above first."
            return
        }

        let styleSnapshot = style
        let logoBox = UncheckedLogo(image: logo)
        let showsBoth = hasLogo || styleSnapshot != QRStyle()
        let queueDetails = queueDetailsIfEnabled
        let keepBasePageWhileRestyling = !queueDetailsIfEnabled && selectedPreviewPage == .base
        let baseStyle = QRStyle()
        generateSerial += 1
        let serial = generateSerial
        isGenerating = true

        generateTask = Task(priority: .userInitiated) {
            let rendered = await Task.detached(priority: .userInitiated) { () -> RenderedQR? in
                let generator = QRCodeGenerator()
                let logoSnapshot = logoBox.image
                guard let base = generator.makeImage(from: payload, style: baseStyle, logo: nil),
                      let styled = generator.makeImage(from: payload, style: styleSnapshot, logo: logoSnapshot) else {
                    return nil
                }

                return RenderedQR(
                    base: base,
                    styled: styled,
                    basePNGURL: generator.writePNG(base, named: "QRCode-Base"),
                    styledPNGURL: generator.writePNG(styled, named: "QRCode-Styled"),
                    basePDFURL: generator.writePDF(from: payload, style: baseStyle, logo: nil, named: "QRCode-Base"),
                    styledPDFURL: generator.writePDF(from: payload, style: styleSnapshot, logo: logoSnapshot, named: "QRCode-Styled"),
                    baseSVGURL: generator.writeSVG(from: payload, style: baseStyle, logo: nil, named: "QRCode-Base"),
                    styledSVGURL: generator.writeSVG(from: payload, style: styleSnapshot, logo: logoSnapshot, named: "QRCode-Styled"),
                    basePNGData: generator.pngData(from: base),
                    styledPNGData: showsBoth ? generator.pngData(from: styled) : nil
                )
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard serial == self.generateSerial else { return }
                self.isGenerating = false

                guard let rendered else {
                    self.clearResult()
                    self.message = "Fill in the fields above first."
                    return
                }

                self.baseCGImage = rendered.base
                self.styledCGImage = rendered.styled
                self.baseImage = Image(decorative: rendered.base, scale: 1)
                self.styledImage = Image(decorative: rendered.styled, scale: 1)
                self.basePNGURL = rendered.basePNGURL
                self.styledPNGURL = rendered.styledPNGURL
                self.basePDFURL = rendered.basePDFURL
                self.styledPDFURL = rendered.styledPDFURL
                self.baseSVGURL = rendered.baseSVGURL
                self.styledSVGURL = rendered.styledSVGURL

                if !showsBoth {
                    self.selectedPreviewPage = .base
                } else if keepBasePageWhileRestyling {
                    // Keep page while restyling.
                } else if queueDetails {
                    self.selectedPreviewPage = .styled
                }

                if queueDetails {
                    let record = self.saveToHistory(
                        payload,
                        baseImageData: rendered.basePNGData,
                        styledImageData: rendered.styledPNGData
                    )
                    self.lastRecord = record

                    if let url = self.persistence.websiteToOpenAutomatically(payload) {
                        self.pendingWebsiteURL = url
                        return
                    }

                    if SettingsKey.isOn(SettingsKey.showDetailsAutomatically) {
                        self.pendingDetailRecord = record
                    }
                }
            }
        }
    }

    /// Waits until the in-flight generate task finishes (used by Create before dismiss).
    func generateAndWait(queueDetailsIfEnabled: Bool = false) async {
        generate(queueDetailsIfEnabled: queueDetailsIfEnabled)
        await generateTask?.value
    }

    func saveToPhotos() async {
        guard let cgImage = activeCGImage else { return }
        guard !isSavedToPhotos else { return }

        let data = QRCodeGenerator().pngData(from: cgImage)
        guard let data else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = "Photos access denied."
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
            message = "Could not save the image."
        }
    }

    func clear() {
        clearResult()
        input = QRInput()
        style = QRStyle()
        logo = nil
        hasLogo = false
    }

    func setLogo(_ data: Data?) {
        guard let data, let image = Self.makeCGImage(from: data) else { return }

        logo = image
        hasLogo = true
        style.correction = .high
        redrawIfNeeded()
    }

    func removeLogo() {
        logo = nil
        hasLogo = false
        redrawIfNeeded()
    }

    private func redrawIfNeeded() {
        guard baseImage != nil || styledImage != nil || isGenerating else { return }
        generate()
    }

    private func clearResult() {
        generateTask?.cancel()
        generateTask = nil
        generateSerial += 1
        isGenerating = false
        saveResetTask?.cancel()
        saveResetTask = nil
        styledImage = nil
        baseImage = nil
        styledPNGURL = nil
        basePNGURL = nil
        styledPDFURL = nil
        basePDFURL = nil
        styledSVGURL = nil
        baseSVGURL = nil
        styledCGImage = nil
        baseCGImage = nil
        message = nil
        lastRecord = nil
        isSavedToPhotos = false
        pendingDetailRecord = nil
        pendingWebsiteURL = nil
        selectedPreviewPage = .styled
    }

    @discardableResult
    private func saveToHistory(_ value: String,
                               baseImageData: Data?,
                               styledImageData: Data?) -> CodeRecord {
        let record = CodeRecord(
            value: value,
            kind: .created,
            baseImageData: baseImageData,
            styledImageData: styledImageData
        )
        if SettingsKey.isOn(SettingsKey.saveHistory) {
            modelContext?.insert(record)
        }
        return record
    }

    private static func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

private struct UncheckedLogo: @unchecked Sendable {
    let image: CGImage?
}

private struct RenderedQR: @unchecked Sendable {
    let base: CGImage
    let styled: CGImage
    let basePNGURL: URL?
    let styledPNGURL: URL?
    let basePDFURL: URL?
    let styledPDFURL: URL?
    let baseSVGURL: URL?
    let styledSVGURL: URL?
    let basePNGData: Data?
    let styledPNGData: Data?
}
