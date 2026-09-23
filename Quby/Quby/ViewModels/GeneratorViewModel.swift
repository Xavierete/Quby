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

    /// Set when Create should open details after the creation sheet dismisses.
    var pendingDetailRecord: CodeRecord?
    /// Set when Create should open a safe website in WebKit after the sheet dismisses.
    var pendingWebsiteURL: URL?

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private let generator = QRCodeGenerator()
    @ObservationIgnored private let builder = QRPayloadBuilder()
    @ObservationIgnored private let persistence = CodeScanPersistence()
    @ObservationIgnored private var styledCGImage: CGImage?
    @ObservationIgnored private var baseCGImage: CGImage?
    @ObservationIgnored private var logo: CGImage?
    @ObservationIgnored private var saveResetTask: Task<Void, Never>?

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
        saveResetTask?.cancel()
        saveResetTask = nil
        message = nil
        isSavedToPhotos = false

        guard let payload = builder.payload(for: type, input: input) else {
            clearResult()
            message = "Fill in the fields above first."
            return
        }

        let baseStyle = QRStyle()
        guard let base = generator.makeImage(from: payload, style: baseStyle, logo: nil),
              let styled = generator.makeImage(from: payload, style: style, logo: logo) else {
            clearResult()
            message = "Fill in the fields above first."
            return
        }

        baseCGImage = base
        styledCGImage = styled
        baseImage = Image(decorative: base, scale: 1)
        styledImage = Image(decorative: styled, scale: 1)

        basePNGURL = generator.writePNG(base, named: "QRCode-Base")
        styledPNGURL = generator.writePNG(styled, named: "QRCode-Styled")
        basePDFURL = generator.writePDF(from: payload, style: baseStyle, logo: nil, named: "QRCode-Base")
        styledPDFURL = generator.writePDF(from: payload, style: style, logo: logo, named: "QRCode-Styled")
        baseSVGURL = generator.writeSVG(from: payload, style: baseStyle, logo: nil, named: "QRCode-Base")
        styledSVGURL = generator.writeSVG(from: payload, style: style, logo: logo, named: "QRCode-Styled")

        if !showsBothPreviews {
            selectedPreviewPage = .base
        } else if selectedPreviewPage == .base && !queueDetailsIfEnabled {
            // Keep page while restyling.
        } else if queueDetailsIfEnabled {
            selectedPreviewPage = .styled
        }

        // Only Create inserts history (always a new row, even if the value already exists).
        // Style redraws must not spam History.
        if queueDetailsIfEnabled {
            let record = saveToHistory(
                payload,
                baseImage: base,
                styledImage: showsBothPreviews ? styled : nil
            )
            lastRecord = record

            if let url = persistence.websiteToOpenAutomatically(payload) {
                pendingWebsiteURL = url
                return
            }

            if SettingsKey.isOn(SettingsKey.showDetailsAutomatically) {
                pendingDetailRecord = record
            }
        }
    }

    func saveToPhotos() async {
        guard let cgImage = activeCGImage,
              let data = generator.pngData(from: cgImage) else { return }
        guard !isSavedToPhotos else { return }

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
        guard baseImage != nil || styledImage != nil else { return }
        generate()
    }

    private func clearResult() {
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
                               baseImage: CGImage,
                               styledImage: CGImage?) -> CodeRecord {
        let record = CodeRecord(
            value: value,
            kind: .created,
            baseImageData: generator.pngData(from: baseImage),
            styledImageData: styledImage.flatMap { generator.pngData(from: $0) }
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
