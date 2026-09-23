import Vision

enum BarcodeLabels {

    static func displayName(for symbology: BarcodeSymbology) -> String {
        switch symbology {
        case .qr: return "QR code"
        case .microQR: return "Micro QR"
        case .aztec: return "Aztec"
        case .dataMatrix: return "Data Matrix"
        case .pdf417: return "PDF417"
        case .microPDF417: return "Micro PDF417"
        case .ean8: return "EAN-8"
        case .ean13: return "EAN-13"
        case .upce: return "UPC-E"
        case .code39: return "Code 39"
        case .code93: return "Code 93"
        case .code128: return "Code 128"
        case .itf14: return "ITF-14"
        case .i2of5: return "Interleaved 2 of 5"
        case .codabar: return "Codabar"
        case .gs1DataBar, .gs1DataBarLimited, .gs1DataBarExpanded: return "GS1 DataBar"
        default: return "Barcode"
        }
    }

    static let preferredSymbologies: [BarcodeSymbology] = [
        .qr, .microQR, .aztec, .dataMatrix, .pdf417, .microPDF417,
        .ean8, .ean13, .upce, .code39, .code93, .code128,
        .itf14, .i2of5, .codabar,
        .gs1DataBar, .gs1DataBarLimited, .gs1DataBarExpanded
    ]
}
