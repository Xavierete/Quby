import AVFoundation
import CoreImage

/// Live camera scanner using AVFoundation metadata output (Apple's recommended
/// path for custom camera UI). Nearby context is enriched with Vision's
/// `RecognizeDocumentsRequest` on a captured frame.
final class CameraScanner: NSObject,
                           AVCaptureMetadataOutputObjectsDelegate,
                           AVCaptureVideoDataOutputSampleBufferDelegate,
                           @unchecked Sendable {

    var onCodeFound: ((DetectedCode) -> Void)?
    var onFrame: ((CGImage) -> Void)?
    var onContextEnriched: ((String, [ScanContextField]) -> Void)?

    private let session = AVCaptureSession()
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let sessionQueue = DispatchQueue(label: "quby.camera.session")
    private let outputQueue = DispatchQueue(label: "quby.camera.output", qos: .userInitiated)
    private var device: AVCaptureDevice?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var isConfigured = false
    private var latestFrame: CGImage?
    private var lastPreviewPublishTime = CFAbsoluteTimeGetCurrent()
    private let contextExtractor = NearbyScanContextExtractor()
    private var enrichingValue: String?

    private static let wantedObjectTypes: [AVMetadataObject.ObjectType] = [
        .qr, .microQR, .aztec, .dataMatrix, .pdf417, .microPDF417,
        .ean8, .ean13, .upce, .code39, .code39Mod43, .code93, .code128,
        .itf14, .interleaved2of5, .codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited
    ]

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    @discardableResult
    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard let device = Self.preferredCamera(),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        self.device = device

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else { return false }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: outputQueue)
        self.metadataOutput = metadataOutput
        applyObjectTypes()

        let videoOutput = AVCaptureVideoDataOutput()
        guard session.canAddOutput(videoOutput) else { return false }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        if let connection = videoOutput.connection(with: .video) {
            let angle: CGFloat = 90
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        isConfigured = true
        return true
    }

    /// Prefer the back camera on iPhone; fall back to any available video device (Mac / Continuity).
    private static func preferredCamera() -> AVCaptureDevice? {
        if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return back
        }
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return front
        }
        if let anyDefault = AVCaptureDevice.default(for: .video) {
            return anyDefault
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .continuityCamera,
                .external
            ],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first
    }

    /// Starts the session. Completes on the main queue with whether a camera is available.
    func start(completion: @escaping @MainActor (Bool) -> Void) {
        sessionQueue.async {
            let ready = self.configureIfNeeded()
            if ready, !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                completion(ready)
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.setTorchOnSessionQueue(false)
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.latestFrame = nil
                self.enrichingValue = nil
            }
        }
    }

    private func applyObjectTypes() {
        guard let output = metadataOutput else { return }
        let supported = output.availableMetadataObjectTypes
        output.metadataObjectTypes = Self.wantedObjectTypes.filter { supported.contains($0) }
    }

    func setTorch(_ isOn: Bool) {
        sessionQueue.async {
            self.setTorchOnSessionQueue(isOn)
        }
    }

    var hasTorch: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if let device {
            return device.hasTorch && device.isTorchAvailable
        }
        return preferredCameraHasTorch
        #endif
    }

    private var preferredCameraHasTorch: Bool {
        Self.preferredCamera()?.hasTorch == true
    }

    func focus(at point: CGPoint) {
        sessionQueue.async {
            guard let device = self.device else { return }
            guard (try? device.lockForConfiguration()) != nil else { return }

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }

            device.unlockForConfiguration()
        }
    }

    private func setTorchOnSessionQueue(_ isOn: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = isOn ? .on : .off
        device.unlockForConfiguration()
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }

        let code = DetectedCode(value: value, symbology: Self.label(for: object.type))
        DispatchQueue.main.async {
            let frame = self.latestFrame
            self.onCodeFound?(code)
            self.enrichContext(for: value, frame: frame)
        }
    }

    private func enrichContext(for value: String, frame: CGImage?) {
        guard let frame else { return }
        guard enrichingValue != value else { return }
        enrichingValue = value

        Task(priority: .utility) {
            let fields = await self.contextExtractor.extract(from: frame, codeValue: value)
            await MainActor.run {
                guard self.enrichingValue == value else { return }
                self.enrichingValue = nil
                guard !fields.isEmpty else { return }
                self.onContextEnriched?(value, fields)
            }
        }
    }

    nonisolated private static func label(for type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr: return "QR code"
        case .microQR: return "Micro QR"
        case .aztec: return "Aztec"
        case .dataMatrix: return "Data Matrix"
        case .pdf417: return "PDF417"
        case .microPDF417: return "Micro PDF417"
        case .ean8: return "EAN-8"
        case .ean13: return "EAN-13"
        case .upce: return "UPC-E"
        case .code39: return "Code 39"
        case .code39Mod43: return "Code 39 mod 43"
        case .code93: return "Code 93"
        case .code128: return "Code 128"
        case .itf14: return "ITF-14"
        case .interleaved2of5: return "Interleaved 2 of 5"
        case .codabar: return "Codabar"
        case .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited: return "GS1 DataBar"
        default: return "Barcode"
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvImageBuffer: buffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        DispatchQueue.main.async {
            self.latestFrame = cgImage
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastPreviewPublishTime >= (1.0 / 15.0) else { return }
            self.lastPreviewPublishTime = now
            self.onFrame?(cgImage)
        }
    }
}
