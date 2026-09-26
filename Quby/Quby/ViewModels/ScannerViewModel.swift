import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

@Observable
final class ScannerViewModel {

    enum Status {
        case idle
        case scanning
        case denied
        case unavailable
    }

    private(set) var status: Status = .idle
    private(set) var lastScan: CodeRecord?
    private(set) var message: String?
    private(set) var isTorchOn = false
    private(set) var hasTorch = false
    private(set) var autoOpenURL: URL?

    var isShowingDetails = false
    private(set) var scanCount = 0

    /// HD preset aspect used for tap-to-focus mapping with aspect-fill preview.
    var previewAspect: CGFloat { 1280.0 / 720.0 }

    var captureSession: AVCaptureSession { scanner.captureSession }

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private let scanner = CameraScanner()
    @ObservationIgnored private let photoScanService = PhotoScanService()
    @ObservationIgnored private let persistence = CodeScanPersistence()

    init() {
        scanner.onCodeFound = { [weak self] code in
            self?.handle(code)
        }
        scanner.onContextEnriched = { [weak self] value, fields in
            self?.applyContext(value: value, fields: fields)
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
        await withCheckedContinuation { continuation in
            scanner.start { [weak self] ready in
                guard let self else {
                    continuation.resume()
                    return
                }
                if ready {
                    self.status = .scanning
                    self.hasTorch = self.scanner.hasTorch
                } else {
                    self.status = .unavailable
                    self.hasTorch = false
                }
                continuation.resume()
            }
        }
        #endif
    }

    func stop() {
        scanner.stop()
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

        #if os(iOS)
        // Preview is rotated 90° relative to the sensor on iPhone.
        scanner.focus(at: CGPoint(x: y, y: 1 - x))
        #else
        scanner.focus(at: CGPoint(x: x, y: y))
        #endif
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
        guard !isShowingDetails else { return }

        persistScan(code)

        if let url = persistence.websiteToOpenAutomatically(code.value) {
            autoOpenURL = url
            return
        }

        guard SettingsKey.isOn(SettingsKey.showDetailsAutomatically) else { return }
        openDetails()
    }

    @discardableResult
    private func persistScan(_ code: DetectedCode) -> CodeRecord {
        let record = persistence.save(code, in: modelContext, source: .camera)
        lastScan = record

        if SettingsKey.isOn(SettingsKey.scanHaptics) {
            scanCount += 1
        }

        return record
    }

    private func applyContext(value: String, fields: [ScanContextField]) {
        guard let lastScan, lastScan.value == value else { return }
        lastScan.nearbyContext = fields
    }

    func autoOpenHandled() {
        autoOpenURL = nil
    }

    /// Opens details and stops camera detection until the sheet is dismissed.
    func openDetails() {
        guard lastScan != nil else { return }
        guard !isShowingDetails else { return }
        isShowingDetails = true
        pauseDetection()
    }

    func detailsDismissed() {
        isShowingDetails = false
        resumeDetection()
    }

    private func pauseDetection() {
        scanner.stop()
        isTorchOn = false
        if status == .scanning {
            status = .idle
        }
    }

    private func resumeDetection() {
        #if targetEnvironment(simulator)
        return
        #else
        scanner.start { [weak self] ready in
            guard let self else { return }
            if ready {
                self.status = .scanning
                self.hasTorch = self.scanner.hasTorch
            } else {
                self.status = .unavailable
                self.hasTorch = false
            }
        }
        #endif
    }
}
