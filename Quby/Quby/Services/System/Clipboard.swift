import UIKit

struct Clipboard {

    func copy(text: String) {
        UIPasteboard.general.string = text
    }

    func pasteText() -> String? {
        UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    func copy(image: CGImage) {
        UIPasteboard.general.image = UIImage(cgImage: image)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
