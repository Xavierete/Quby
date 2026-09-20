import UIKit

struct Clipboard {

    func copy(text: String) {
        UIPasteboard.general.string = text
    }

    func copy(image: CGImage) {
        UIPasteboard.general.image = UIImage(cgImage: image)
    }
}
