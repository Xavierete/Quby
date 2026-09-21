import Foundation
import SwiftData

struct PhotoScanService {

    private let decoder = PhotoQRDecoder()
    private let persistence = CodeScanPersistence()

    func scan(imageData: Data, modelContext: ModelContext) async -> PhotoScanOutcome {
        guard let code = await decoder.decode(imageData: imageData) else {
            return .failure("No code found in that image.")
        }

        let record = persistence.save(code, in: modelContext)

        if let url = persistence.websiteToOpenAutomatically(code.value) {
            return .openURL(url)
        }
        return .success(record)
    }
}
