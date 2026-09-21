import Foundation
import SwiftData

enum PhotoScanOutcome {
    case success(CodeRecord)
    case openURL(URL)
    case failure(String)
    case cancelled
}

struct CodeScanPersistence {

    private let parser = ScannedContentParser()
    private let safety = LinkSafety()
    private let sound = SoundPlayer()

    @discardableResult
    func save(_ code: DetectedCode, in modelContext: ModelContext?) -> CodeRecord {
        let record = CodeRecord(value: code.value, kind: .scanned, symbology: code.symbology)
        if SettingsKey.isOn(SettingsKey.saveHistory) {
            modelContext?.insert(record)
        }
        if SettingsKey.isOn(SettingsKey.scanSound) {
            sound.playScanSound()
        }
        return record
    }

    func websiteToOpenAutomatically(_ value: String) -> URL? {
        guard SettingsKey.isOn(SettingsKey.openWebsitesAutomatically),
              case .website(let url) = parser.parse(value),
              safety.warnings(for: url).isEmpty else { return nil }
        return url
    }
}
