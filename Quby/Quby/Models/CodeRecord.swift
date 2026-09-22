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
    var baseImageData: Data?
    /// Styled look from Create (palette, shape, logo).
    var styledImageData: Data?

    init(value: String,
         kind: CodeKind,
         createdAt: Date = Date(),
         isFavorite: Bool = false,
         symbology: String = "QR code",
         baseImageData: Data? = nil,
         styledImageData: Data? = nil) {
        self.value = value
        self.kind = kind
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.symbology = symbology
        self.baseImageData = baseImageData
        self.styledImageData = styledImageData
    }
}
