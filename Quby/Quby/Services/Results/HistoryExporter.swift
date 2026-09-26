import CoreGraphics
import Foundation
import ImageIO

struct HistoryExporter {

    private let generator = QRCodeGenerator()
    private let parser = ScannedContentParser()

    func plainText(_ records: [CodeRecord]) -> String {
        records.map(\.value).joined(separator: "\n")
    }

    func json(_ records: [CodeRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let payload: [[String: Any]] = records.enumerated().map { index, record in
            [
                "id": String(format: "%03d", index + 1),
                "value": record.value,
                "type": parser.parse(record.value).title,
                "kind": record.kind == .created ? "created" : "scanned",
                "symbology": record.symbology,
                "created": formatter.string(from: record.createdAt),
                "favourite": record.isFavorite
            ]
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "[]\n"
        }
        return string + "\n"
    }

    /// Flat CSV (no images) — useful for spreadsheets that only need data.
    func csv(_ records: [CodeRecord], imageNames: [String?] = []) -> String {
        let header = [
            "id",
            "value",
            "type",
            "kind",
            "symbology",
            "created",
            "favourite",
            "image"
        ].joined(separator: ",")

        let rows = records.enumerated().map { index, record in
            let imageName = imageNames.indices.contains(index) ? (imageNames[index] ?? "") : ""
            let fields = rowFields(for: record, id: index + 1)
            return [
                quoted(fields.id),
                quoted(fields.value),
                quoted(fields.type),
                quoted(fields.kind),
                quoted(fields.symbology),
                quoted(fields.created),
                fields.favourite,
                quoted(imageName)
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    func writeText(_ records: [CodeRecord]) -> URL? {
        write(string: plainText(records), named: "Quby codes.txt")
    }

    /// CSV only (no image files).
    func writeCSV(_ records: [CodeRecord]) -> URL? {
        write(string: csv(records), named: "Quby codes.csv")
    }

    /// ZIP with `codes.csv` plus `images/001.png`… for each code.
    func writeCSVPackage(_ records: [CodeRecord]) -> URL? {
        guard !records.isEmpty else { return nil }

        var entries: [(path: String, data: Data)] = []
        var imageNames: [String?] = []

        for (index, record) in records.enumerated() {
            let id = String(format: "%03d", index + 1)
            if let png = pngData(for: record) {
                let relative = "images/\(id).png"
                entries.append((relative, png))
                imageNames.append(relative)
            } else {
                imageNames.append(nil)
            }
        }

        guard let csvData = csv(records, imageNames: imageNames).data(using: .utf8) else { return nil }
        entries.insert(("codes.csv", csvData), at: 0)

        return writeZip(entries: entries, named: "Quby codes.zip")
    }

    func writeJSON(_ records: [CodeRecord]) -> URL? {
        write(string: json(records), named: "Quby codes.json")
    }

    /// Excel workbook (.xlsx) without embedded images.
    func writeExcel(_ records: [CodeRecord]) -> URL? {
        guard !records.isEmpty else { return nil }
        do {
            let data = try ExcelWorkbookBuilder(
                records: records,
                images: [],
                includeImages: false,
                parser: parser
            ).build()
            return write(data: data, named: "Quby codes.xlsx")
        } catch {
            return nil
        }
    }

    /// Excel workbook (.xlsx) with a QR image on each selected row.
    func writeExcelWithImages(_ records: [CodeRecord]) -> URL? {
        guard !records.isEmpty else { return nil }

        // One PNG slot per selected record (same order) so every row can get a QR.
        let images: [Data?] = records.map { pngData(for: $0) }
        do {
            let data = try ExcelWorkbookBuilder(
                records: records,
                images: images,
                includeImages: true,
                parser: parser
            ).build()
            return write(data: data, named: "Quby codes with images.xlsx")
        } catch {
            return nil
        }
    }

    /// PDF table without QR images.
    func writePDF(_ records: [CodeRecord]) -> URL? {
        writePDF(records, includeImages: false, named: "Quby codes.pdf")
    }

    /// PDF table with a QR thumbnail per row.
    func writePDFWithImages(_ records: [CodeRecord]) -> URL? {
        writePDF(records, includeImages: true, named: "Quby codes with images.pdf")
    }

    private func writePDF(_ records: [CodeRecord], includeImages: Bool, named name: String) -> URL? {
        guard !records.isEmpty else { return nil }
        let images: [CGImage?] = includeImages
            ? records.map { exportImage(for: $0) }
            : []

        do {
            let data = try PDFTableBuilder(
                records: records,
                images: images,
                includeImages: includeImages,
                parser: parser
            ).build()
            return write(data: data, named: name)
        } catch {
            return nil
        }
    }

    private struct RowFields {
        let id: String
        let value: String
        let type: String
        let kind: String
        let symbology: String
        let created: String
        let favourite: String
    }

    private func rowFields(for record: CodeRecord, id: Int) -> RowFields {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return RowFields(
            id: String(format: "%03d", id),
            value: record.value,
            type: parser.parse(record.value).title,
            kind: record.kind == .created ? "created" : "scanned",
            symbology: record.symbology,
            created: formatter.string(from: record.createdAt),
            favourite: record.isFavorite ? "yes" : "no"
        )
    }

    /// Prefer stored bitmaps; otherwise regenerate a QR with Core Image.
    private func exportImage(for record: CodeRecord) -> CGImage? {
        if let data = record.styledImageData ?? record.baseImageData,
           let image = cgImage(from: data) {
            return image
        }
        let trimmed = record.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return generator.makeImage(from: trimmed, minimumSize: 512)
    }

    private func pngData(for record: CodeRecord) -> Data? {
        if let data = record.styledImageData ?? record.baseImageData {
            if isPNG(data) {
                return data
            }
            if let image = cgImage(from: data),
               let png = generator.pngData(from: image) {
                return png
            }
        }

        let trimmed = record.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let image = generator.makeImage(from: trimmed, minimumSize: 512),
              let png = generator.pngData(from: image) else {
            return nil
        }
        return png
    }

    private func isPNG(_ data: Data) -> Bool {
        data.count >= 8 && data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    private func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: true
        ] as CFDictionary)
    }

    private func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func write(string: String, named name: String) -> URL? {
        guard let data = string.data(using: .utf8) else { return nil }
        return write(data: data, named: name)
    }

    private func write(data: Data, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func writeZip(entries: [(path: String, data: Data)], named name: String) -> URL? {
        do {
            let data = try ZipStoreArchive.data(from: entries)
            return write(data: data, named: name)
        } catch {
            return nil
        }
    }
}
