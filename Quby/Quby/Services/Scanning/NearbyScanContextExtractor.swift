import Foundation
import Vision
import DataDetection
import CoreGraphics

/// Uses Vision's iOS 26 `RecognizeDocumentsRequest` to pull title / data-detector
/// context (place, phone, email, etc.) from around a scanned code.
struct NearbyScanContextExtractor {

    func extract(from imageData: Data, codeValue: String) async -> [ScanContextField] {
        guard let document = await recognizeDocument(on: imageData) else { return [] }
        return fields(from: document, excludingPayload: codeValue)
    }

    func extract(from cgImage: CGImage, codeValue: String) async -> [ScanContextField] {
        guard let document = await recognizeDocument(on: cgImage) else { return [] }
        return fields(from: document, excludingPayload: codeValue)
    }

    func recognizeDocument(on imageData: Data) async -> DocumentObservation.Container? {
        guard let observations = try? await makeDocumentsRequest().perform(on: imageData) else {
            return nil
        }
        return observations.first?.document
    }

    func recognizeDocument(on cgImage: CGImage) async -> DocumentObservation.Container? {
        guard let observations = try? await makeDocumentsRequest().perform(on: cgImage) else {
            return nil
        }
        return observations.first?.document
    }

    func fields(
        from document: DocumentObservation.Container,
        excludingPayload: String
    ) -> [ScanContextField] {
        var fields: [ScanContextField] = []
        var seen = Set<String>()
        let payloadKey = normalize(excludingPayload)

        func append(_ label: String, _ value: String) {
            let trimmed = collapseSpaces(value)
            guard trimmed.count >= 3, trimmed.count <= 120 else { return }
            let key = normalize(trimmed)
            guard !key.isEmpty, key != payloadKey else { return }
            if payloadKey.contains(key), key.count >= 8 { return }
            guard seen.insert(key).inserted else { return }
            fields.append(ScanContextField(label: label, value: trimmed))
        }

        if let title = document.title?.transcript {
            append("Name", title)
        }

        appendDetectedData(from: document.text, using: append)
        for paragraph in document.paragraphs {
            appendDetectedData(from: paragraph, using: append)
        }

        if fields.count < 3 {
            for line in document.text.lines.prefix(8) {
                guard let text = line.topCandidates(1).first?.string else { continue }
                let label = line.isTitle ? "Name" : "Nearby text"
                append(label, text)
                if fields.count >= 3 { break }
            }
        }

        return Array(fields.prefix(3))
    }

    private func appendDetectedData(
        from text: DocumentObservation.Container.Text,
        using append: (String, String) -> Void
    ) {
        for match in text.detectedData {
            switch match.match.details {
            case .emailAddress(let email):
                append("Email", email.emailAddress)
            case .phoneNumber(let phone):
                append("Phone", phone.phoneNumber)
            case .postalAddress(let address):
                append("Place", address.fullAddress)
            case .link(let link):
                append("Website", link.url.absoluteString)
            case .shipmentTrackingNumber(let shipment):
                append("Tracking", shipment.trackingNumber)
            case .flightNumber(let flight):
                append("Flight", "\(flight.airlineCode)\(flight.flightNumber)")
            default:
                break
            }
        }
    }

    private func makeDocumentsRequest() -> RecognizeDocumentsRequest {
        var request = RecognizeDocumentsRequest()

        var textOptions = request.textRecognitionOptions
        textOptions.automaticallyDetectLanguage = true
        textOptions.useLanguageCorrection = true
        request.textRecognitionOptions = textOptions

        var barcodeOptions = request.barcodeDetectionOptions
        barcodeOptions.enabled = true
        let supported = Set(request.supportedBarcodeSymbologies)
        barcodeOptions.symbologies = BarcodeLabels.preferredSymbologies.filter(supported.contains)
        request.barcodeDetectionOptions = barcodeOptions

        return request
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    private func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
