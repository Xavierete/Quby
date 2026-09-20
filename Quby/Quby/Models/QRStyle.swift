import Foundation

struct CodeColor: Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    static let black = CodeColor(red: 0, green: 0, blue: 0)
    static let white = CodeColor(red: 1, green: 1, blue: 1)
}

enum QRModuleStyle: String {
    case square
}

enum QRCorrection: String {
    case medium = "M"
}

struct QRStyle: Equatable {
    var foreground: CodeColor = .black
    var background: CodeColor = .white
    var module: QRModuleStyle = .square
    var correction: QRCorrection = .medium
}
