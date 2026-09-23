import Foundation

struct DetectedCode {
    let value: String
    let symbology: String
    var context: [ScanContextField] = []
}
