import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct Clipboard {

    func copy(text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    func pasteText() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        #else
        return UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        #endif
    }

    func copy(image: CGImage) {
        #if os(macOS)
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
        #else
        UIPasteboard.general.image = UIImage(cgImage: image)
        #endif
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
