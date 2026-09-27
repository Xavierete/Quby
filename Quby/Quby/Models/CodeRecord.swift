import Foundation
import SwiftData

enum CodeKind: String, Codable {
    case scanned
    case created
}

/// Persistent QR / barcode entry shown in History (and created from Scan / Create).
@Model
final class CodeRecord {

    var value: String = ""
    var kind: CodeKind = CodeKind.scanned
    var createdAt: Date = Date()
    var isFavorite: Bool = false
    var symbology: String = "QR code"
    /// Classic / unscanned look.
    @Attribute(.externalStorage) var baseImageData: Data?
    /// Styled look from Create (palette, shape, logo).
    @Attribute(.externalStorage) var styledImageData: Data?
    /// Nearby OCR from the photo/camera frame (name, place, sign text), stored as JSON.
    var nearbyContextJSON: String = "[]"

    // MARK: - Apple Intelligence organization (HistorySmartOrganizer)
    /// Section title from smart organize; empty means not organized yet.
    var smartGroupTitle: String = ""
    /// Short list title from smart organize; empty falls back to raw `value`.
    var smartTitle: String = ""
    /// Stable order inside a smart group (lower first).
    var smartSortIndex: Int = 0

    /// Decoded nearby OCR fields (backed by `nearbyContextJSON`).
    var nearbyContext: [ScanContextField] {
        get {
            guard let data = nearbyContextJSON.data(using: .utf8),
                  let fields = try? JSONDecoder().decode([ScanContextField].self, from: data) else {
                return []
            }
            return fields
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                nearbyContextJSON = json
            } else {
                nearbyContextJSON = "[]"
            }
        }
    }

    init(value: String,
         kind: CodeKind,
         createdAt: Date = Date(),
         isFavorite: Bool = false,
         symbology: String = "QR code",
         baseImageData: Data? = nil,
         styledImageData: Data? = nil,
         nearbyContext: [ScanContextField] = []) {
        self.value = value
        self.kind = kind
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.symbology = symbology
        self.baseImageData = baseImageData
        self.styledImageData = styledImageData
        self.nearbyContext = nearbyContext
        self.smartGroupTitle = ""
        self.smartTitle = ""
        self.smartSortIndex = 0
    }

    /// Whether this row belongs to a smart-organized section.
    var isSmartOrganized: Bool {
        !smartGroupTitle.isEmpty
    }

    /// Preferred History row title (smart title when present).
    var listTitle: String {
        let trimmed = smartTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? value : trimmed
    }
}
