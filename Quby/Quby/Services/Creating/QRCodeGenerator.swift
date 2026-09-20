import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

struct QRCodeGenerator {

    private let context = CIContext()

    func makeImage(from text: String,
                   style: QRStyle = QRStyle(),
                   minimumSize: CGFloat = 1024) -> CGImage? {
        guard let modules = extractModules(from: text, correction: style.correction) else { return nil }

        let rows = modules.count
        let columns = modules[0].count
        let scale = max(1, (minimumSize / CGFloat(columns)).rounded(.up))
        let width = Int(CGFloat(columns) * scale)
        let height = Int(CGFloat(rows) * scale)

        guard let canvas = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        canvas.setFillColor(cgColor(style.background))
        canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
        canvas.setFillColor(cgColor(style.foreground))

        for row in 0..<rows {
            for column in 0..<columns where modules[row][column] {
                let rect = CGRect(
                    x: CGFloat(column) * scale,
                    y: CGFloat(rows - row - 1) * scale,
                    width: scale,
                    height: scale
                )
                canvas.fill(rect)
            }
        }

        return canvas.makeImage()
    }

    private func extractModules(from text: String, correction: QRCorrection) -> [[Bool]]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(trimmed.utf8)
        filter.correctionLevel = correction.rawValue

        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        return modules(from: output)
    }

    private func modules(from image: CIImage) -> [[Bool]]? {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        guard width > 0, height > 0,
              let cgImage = context.createCGImage(image, from: image.extent) else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let reader = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        reader.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (0..<height).map { row in
            (0..<width).map { column in
                let offset = (row * width + column) * 4
                return pixels[offset] < 128
            }
        }
    }

    private func cgColor(_ color: CodeColor) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}
