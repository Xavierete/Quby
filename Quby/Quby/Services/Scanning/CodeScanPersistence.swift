import Foundation
import SwiftData

enum PhotoScanOutcome {
    case success(CodeRecord)
    case openURL(URL)
    case failure(String)
    case cancelled
}

struct CodeScanPersistence {

    enum Source {
        case camera
        case photo
    }

    private let parser = ScannedContentParser()
    private let safety = LinkSafety()
    private let sound = SoundPlayer()

    @discardableResult
    func save(_ code: DetectedCode, in modelContext: ModelContext?, source: Source) -> CodeRecord {
        let record = CodeRecord(
            value: code.value,
            kind: .scanned,
            symbology: code.symbology,
            nearbyContext: code.context
        )
        if shouldSaveToHistory(source) {
            modelContext?.insert(record)
        }
        if SettingsKey.isOn(SettingsKey.scanSound) {
            sound.playScanSound()
        }
        return record
    }

    private func shouldSaveToHistory(_ source: Source) -> Bool {
        switch source {
        case .camera:
            return SettingsKey.isOn(SettingsKey.saveCameraScans)
        case .photo:
            return SettingsKey.isOn(SettingsKey.saveHistory)
        }
    }

    func websiteToOpenAutomatically(_ value: String) -> URL? {
        guard SettingsKey.isOn(SettingsKey.openWebsitesAutomatically),
              case .website(let url) = parser.parse(value),
              safety.warnings(for: url).isEmpty else { return nil }
        return url
    }
}
