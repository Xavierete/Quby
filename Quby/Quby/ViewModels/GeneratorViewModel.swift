import SwiftUI
import SwiftData
import ImageIO
import UIKit

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

    private(set) var qrImage: Image?
    private(set) var message: String?

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private let generator = QRCodeGenerator()
    @ObservationIgnored private let builder = QRPayloadBuilder()
    @ObservationIgnored private var logo: CGImage?

    var canGenerate: Bool {
        builder.payload(for: type, input: input) != nil
    }

    func generate() {
        message = nil

        guard let payload = builder.payload(for: type, input: input),
              let image = generator.makeImage(from: payload, style: style, logo: logo) else {
            clearResult()
            message = "Fill in the fields above first."
            return
        }

        qrImage = Image(decorative: image, scale: 1)
        addToHistory(payload)
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
        guard qrImage != nil else { return }
        generate()
    }

    private func clearResult() {
        qrImage = nil
        message = nil
    }

    private func addToHistory(_ value: String) {
        guard SettingsKey.isOn(SettingsKey.saveHistory) else { return }
        guard let modelContext else { return }

        var descriptor = FetchDescriptor<CodeRecord>(
            predicate: #Predicate { $0.value == value },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty { return }
        modelContext.insert(CodeRecord(value: value, kind: .created))
    }

    private static func makeCGImage(from data: Data) -> CGImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        return UIImage(data: data)?.cgImage
    }
}
