import Foundation
import SwiftData

enum CodeKind: String, Codable {
    case scanned
    case created
}

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
    /// Nearby OCR from the photo/camera frame (name, place, sign text).
    var nearbyContextJSON: String = "[]"
    /// Apple Intelligence section title; empty means not smart-organized.
    var smartGroupTitle: String = ""
    /// Short list title from Apple Intelligence; empty falls back to `value`.
    var smartTitle: String = ""
    /// Order inside a smart group (lower first).
    var smartSortIndex: Int = 0

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

    var isSmartOrganized: Bool {
        !smartGroupTitle.isEmpty
    }

    var listTitle: String {
        let trimmed = smartTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? value : trimmed
    }
}
