import Foundation
import Vision

struct PhotoQRDecoder {

    private let contextExtractor = NearbyScanContextExtractor()

    func decode(imageData: Data) async -> DetectedCode? {
        // Prefer the iOS 26 document API: barcodes + structured context in one pass.
        if let document = await contextExtractor.recognizeDocument(on: imageData),
           let observation = document.barcodes.first(where: { $0.payloadString != nil }),
           let value = observation.payloadString {
            return DetectedCode(
                value: value,
                symbology: BarcodeLabels.displayName(for: observation.symbology),
                context: contextExtractor.fields(from: document, excludingPayload: value)
            )
        }

        // Fallback for sparse images where document parsing misses the code.
        return await decodeBarcodeOnly(imageData: imageData)
    }

    private func decodeBarcodeOnly(imageData: Data) async -> DetectedCode? {
        var request = DetectBarcodesRequest()
        let supported = Set(DetectBarcodesRequest().supportedSymbologies)
        request.symbologies = BarcodeLabels.preferredSymbologies.filter(supported.contains)

        guard let observations = try? await request.perform(on: imageData),
              let observation = observations.first(where: { $0.payloadString != nil }),
              let value = observation.payloadString else { return nil }

        let context = await contextExtractor.extract(from: imageData, codeValue: value)
        return DetectedCode(
            value: value,
            symbology: BarcodeLabels.displayName(for: observation.symbology),
            context: context
        )
    }
}
