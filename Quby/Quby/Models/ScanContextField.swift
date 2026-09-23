import Foundation

struct ScanContextField: Codable, Hashable, Identifiable {
    var id: String { "\(label)|\(value)" }
    let label: String
    let value: String
}
