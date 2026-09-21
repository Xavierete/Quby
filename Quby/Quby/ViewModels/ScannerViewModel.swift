import SwiftUI
import SwiftData
import PhotosUI

@Observable
final class ScannerViewModel {

    enum Status {
        case idle
        case scanning
        case denied
        case unavailable
    }

    private(set) var status: Status = .idle
    private(set) var previewFrame: Image?
    private(set) var previewAspect: CGFloat = 9.0 / 16.0
    private(set) var lastScan: CodeRecord?
    private(set) var message: String?
    private(set) var isTorchOn = false
    private(set) var hasTorch = false
    private(set) var autoOpenURL: URL?

    var isShowingDetails = false
    private(set) var scanCount = 0

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private let scanner = CameraScanner()
    @ObservationIgnored private let photoScanService = PhotoScanService()
    @ObservationIgnored private let persistence = CodeScanPersistence()

    init() {
        scanner.onCodeFound = { [weak self] code in
            self?.handle(code)
        }
        scanner.onFrame = { [weak self] cgImage in
            self?.previewFrame = Image(decorative: cgImage, scale: 1)
            self?.previewAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        }
    }

    func start() async {
        guard await scanner.requestPermission() else {
            status = .denied
            hasTorch = false
            return
        }
        #if targetEnvironment(simulator)
        status = .unavailable
        hasTorch = false
        #else
        scanner.start()
        status = .scanning
        hasTorch = scanner.hasTorch
        #endif
    }

    func stop() {
        scanner.stop()
        previewFrame = nil
        isTorchOn = false
        hasTorch = false
        if status == .scanning { status = .idle }
    }

    func toggleTorch() {
        guard hasTorch else { return }
        isTorchOn.toggle()
        scanner.setTorch(isTorchOn)
    }

    func focus(atTap point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0, previewAspect > 0 else { return }

        let scale = max(size.width / previewAspect, size.height)
        let filledWidth = previewAspect * scale
        let filledHeight = scale

        let x = (point.x + (filledWidth - size.width) / 2) / filledWidth
        let y = (point.y + (filledHeight - size.height) / 2) / filledHeight

        scanner.focus(at: CGPoint(x: y, y: 1 - x))
    }

    func scanPhoto(_ item: PhotosPickerItem?) async -> PhotoScanOutcome {
        guard let item else { return .cancelled }
        guard let modelContext else { return .cancelled }

        guard let data = try? await item.loadTransferable(type: PickedImageData.self) else {
            return .failure("Could not read that image.")
        }

        return await photoScanService.scan(imageData: data.data, modelContext: modelContext)
    }

    func clearResult() {
        lastScan = nil
        message = nil
    }

    private func handle(_ code: DetectedCode) {
        guard lastScan?.value != code.value else { return }

        persistScan(code)

        if let url = persistence.websiteToOpenAutomatically(code.value) {
            autoOpenURL = url
            return
        }

        guard SettingsKey.isOn(SettingsKey.showDetailsAutomatically) else { return }
        scanner.stop()
        isShowingDetails = true
    }

    @discardableResult
    private func persistScan(_ code: DetectedCode) -> CodeRecord {
        let record = persistence.save(code, in: modelContext)
        lastScan = record

        if SettingsKey.isOn(SettingsKey.scanHaptics) {
            scanCount += 1
        }

        return record
    }

    func autoOpenHandled() {
        autoOpenURL = nil
    }

    func detailsDismissed() {
        isShowingDetails = false
        guard status == .scanning else { return }
        scanner.start()
    }
}
