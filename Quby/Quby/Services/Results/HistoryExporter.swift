import CoreGraphics
import CoreText
import Foundation
import ImageIO
import zlib

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
            let data = try ExcelWorkbookBuilder(records: records, images: [], parser: parser)
                .build()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Quby codes.xlsx")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Excel workbook (.xlsx) with a QR image on each row.
    func writeExcelWithImages(_ records: [CodeRecord]) -> URL? {
        guard !records.isEmpty else { return nil }

        let images: [Data?] = records.map { pngData(for: $0) }
        do {
            let data = try ExcelWorkbookBuilder(records: records, images: images, parser: parser)
                .build()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Quby codes.xlsx")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// PDF table without QR images.
    func writePDF(_ records: [CodeRecord]) -> URL? {
        writePDF(records, includeImages: false)
    }

    /// PDF table with a QR thumbnail per row.
    func writePDFWithImages(_ records: [CodeRecord]) -> URL? {
        writePDF(records, includeImages: true)
    }

    private func writePDF(_ records: [CodeRecord], includeImages: Bool) -> URL? {
        guard !records.isEmpty else { return nil }
        let images: [CGImage?] = includeImages
            ? records.map { cgImage(fromPNGData: pngData(for: $0)) }
            : Array(repeating: nil, count: records.count)

        do {
            let data = try PDFTableBuilder(records: records, images: images, parser: parser).build()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Quby codes.pdf")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func cgImage(fromPNGData data: Data?) -> CGImage? {
        guard let data else { return nil }
        return cgImage(from: data)
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

    private func pngData(for record: CodeRecord) -> Data? {
        if let data = record.styledImageData ?? record.baseImageData,
           let image = cgImage(from: data),
           let png = generator.pngData(from: image) {
            return png
        }

        guard let image = generator.makeImage(from: record.value),
              let png = generator.pngData(from: image) else {
            return nil
        }
        return png
    }

    private func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func write(string: String, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try string.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func writeZip(entries: [(path: String, data: Data)], named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try ZipStoreArchive.write(entries: entries, to: url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - PDF table

private struct PDFTableBuilder {

    let records: [CodeRecord]
    let images: [CGImage?]
    let parser: ScannedContentParser

    private var includesImages: Bool {
        images.contains { $0 != nil }
    }

    private let pageSize = CGSize(width: 842, height: 595) // A4 landscape
    private let margin: CGFloat = 28
    private let headerHeight: CGFloat = 22
    private let textRowHeight: CGFloat = 18
    private let imageRowHeight: CGFloat = 64
    private let imageSize: CGFloat = 48

    func build() throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let columns = columnLayout()
        let rowHeight = includesImages ? imageRowHeight : textRowHeight
        let contentTop = pageSize.height - margin
        let contentBottom = margin
        var y = contentTop
        var pageStarted = false

        func beginPage() {
            context.beginPDFPage(nil)
            pageStarted = true
            y = contentTop
            drawTitle(in: context, at: &y)
            drawHeader(in: context, columns: columns, at: &y)
        }

        beginPage()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for (index, record) in records.enumerated() {
            if y - rowHeight < contentBottom {
                context.endPDFPage()
                beginPage()
            }

            let values = [
                String(format: "%03d", index + 1),
                record.value,
                parser.parse(record.value).title,
                record.kind == .created ? "created" : "scanned",
                record.symbology,
                formatter.string(from: record.createdAt),
                record.isFavorite ? "yes" : "no"
            ]

            drawRow(
                in: context,
                columns: columns,
                values: values,
                image: images.indices.contains(index) ? images[index] : nil,
                y: y,
                height: rowHeight,
                zebra: index % 2 == 1
            )
            y -= rowHeight
        }

        if pageStarted {
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private struct Column {
        let title: String
        let width: CGFloat
        let isImage: Bool
    }

    private func columnLayout() -> [Column] {
        let usable = pageSize.width - margin * 2
        var columns: [Column] = [
            Column(title: "ID", width: 36, isImage: false),
            Column(title: "Value", width: 0, isImage: false),
            Column(title: "Type", width: 90, isImage: false),
            Column(title: "Kind", width: 64, isImage: false),
            Column(title: "Symbology", width: 80, isImage: false),
            Column(title: "Created", width: 130, isImage: false),
            Column(title: "Favourite", width: 60, isImage: false)
        ]
        if includesImages {
            columns.append(Column(title: "QR", width: 64, isImage: true))
        }

        let fixed = columns.filter { $0.title != "Value" }.reduce(CGFloat(0)) { $0 + $1.width }
        let valueWidth = max(120, usable - fixed)
        columns[1] = Column(title: "Value", width: valueWidth, isImage: false)
        return columns
    }

    private func drawTitle(in context: CGContext, at y: inout CGFloat) {
        drawText(
            "Quby codes",
            in: context,
            rect: CGRect(x: margin, y: y - 18, width: pageSize.width - margin * 2, height: 18),
            fontSize: 14,
            bold: true,
            color: CGColor(gray: 0.1, alpha: 1)
        )
        y -= 28
    }

    private func drawHeader(in context: CGContext, columns: [Column], at y: inout CGFloat) {
        let rect = CGRect(x: margin, y: y - headerHeight, width: pageSize.width - margin * 2, height: headerHeight)
        context.setFillColor(CGColor(gray: 0.92, alpha: 1))
        context.fill(rect)
        context.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
        context.setLineWidth(0.5)
        context.stroke(rect)

        var x = margin
        for column in columns {
            drawText(
                column.title,
                in: context,
                rect: CGRect(x: x + 4, y: y - headerHeight + 4, width: column.width - 8, height: headerHeight - 6),
                fontSize: 9,
                bold: true,
                color: CGColor(gray: 0.15, alpha: 1)
            )
            x += column.width
        }
        y -= headerHeight
    }

    private func drawRow(
        in context: CGContext,
        columns: [Column],
        values: [String],
        image: CGImage?,
        y: CGFloat,
        height: CGFloat,
        zebra: Bool
    ) {
        let rect = CGRect(x: margin, y: y - height, width: pageSize.width - margin * 2, height: height)
        if zebra {
            context.setFillColor(CGColor(gray: 0.97, alpha: 1))
            context.fill(rect)
        }
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
        context.setLineWidth(0.4)
        context.stroke(rect)

        var x = margin
        for (index, column) in columns.enumerated() {
            let cell = CGRect(x: x + 4, y: y - height + 4, width: column.width - 8, height: height - 8)
            if column.isImage {
                if let image {
                    let side = min(imageSize, cell.width, cell.height)
                    let imageRect = CGRect(
                        x: cell.midX - side / 2,
                        y: cell.midY - side / 2,
                        width: side,
                        height: side
                    )
                    context.saveGState()
                    context.interpolationQuality = .high
                    context.draw(image, in: imageRect)
                    context.restoreGState()
                }
            } else if values.indices.contains(index) {
                drawText(
                    values[index],
                    in: context,
                    rect: cell,
                    fontSize: 8,
                    bold: false,
                    color: CGColor(gray: 0.1, alpha: 1)
                )
            }
            x += column.width
        }
    }

    private func drawText(
        _ string: String,
        in context: CGContext,
        rect: CGRect,
        fontSize: CGFloat,
        bold: Bool,
        color: CGColor
    ) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, fontSize, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        let attributed = CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary)!
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

// MARK: - Excel (.xlsx)

private struct ExcelWorkbookBuilder {

    let records: [CodeRecord]
    let images: [Data?]
    let parser: ScannedContentParser

    private var includesImages: Bool {
        images.contains { $0 != nil }
    }

    func build() throws -> Data {
        var entries: [(path: String, data: Data)] = []

        entries.append(("[Content_Types].xml", Data(contentTypes.utf8)))
        entries.append(("_rels/.rels", Data(rootRels.utf8)))
        entries.append(("xl/workbook.xml", Data(workbook.utf8)))
        entries.append(("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)))
        entries.append(("xl/styles.xml", Data(styles.utf8)))
        entries.append(("xl/worksheets/sheet1.xml", Data(sheetXML.utf8)))

        if includesImages {
            entries.append(("xl/worksheets/_rels/sheet1.xml.rels", Data(sheetRels.utf8)))
            entries.append(("xl/drawings/drawing1.xml", Data(drawingXML.utf8)))
            entries.append(("xl/drawings/_rels/drawing1.xml.rels", Data(drawingRels.utf8)))

            var imageIndex = 0
            for png in images {
                guard let png else { continue }
                imageIndex += 1
                entries.append(("xl/media/image\(imageIndex).png", png))
            }
        }

        return try ZipStoreArchive.data(from: entries)
    }

    private var contentTypes: String {
        var extras = ""
        if includesImages {
            extras = """
            <Default Extension="png" ContentType="image/png"/>
            <Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        \(extras)
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
    }

    private var rootRels: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private var workbook: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
        <sheet name="Codes" sheetId="1" r:id="rId1"/>
        </sheets>
        </workbook>
        """
    }

    private var workbookRels: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private var styles: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2">
          <font><sz val="11"/><name val="Calibri"/></font>
          <font><b/><sz val="11"/><name val="Calibri"/></font>
        </fonts>
        <fills count="2">
          <fill><patternFill patternType="none"/></fill>
          <fill><patternFill patternType="gray125"/></fill>
        </fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf/></cellStyleXfs>
        <cellXfs count="2">
          <xf fontId="0" fillId="0" borderId="0"/>
          <xf fontId="1" fillId="0" borderId="0" applyFont="1"/>
        </cellXfs>
        </styleSheet>
        """
    }

    private var sheetXML: String {
        let headers = ["ID", "Value", "Type", "Kind", "Symbology", "Created", "Favourite"]
            + (includesImages ? ["QR"] : [])

        var rowsXML = "<row r=\"1\">"
        for (column, header) in headers.enumerated() {
            rowsXML += inlineCell(column: column, row: 1, text: header, style: 1)
        }
        rowsXML += "</row>"

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for (index, record) in records.enumerated() {
            let row = index + 2
            let height = includesImages && images.indices.contains(index) && images[index] != nil
                ? " ht=\"96\" customHeight=\"1\""
                : ""
            rowsXML += "<row r=\"\(row)\"\(height)>"
            let values = [
                String(format: "%03d", index + 1),
                record.value,
                parser.parse(record.value).title,
                record.kind == .created ? "created" : "scanned",
                record.symbology,
                formatter.string(from: record.createdAt),
                record.isFavorite ? "yes" : "no"
            ]
            for (column, value) in values.enumerated() {
                rowsXML += inlineCell(column: column, row: row, text: value, style: 0)
            }
            rowsXML += "</row>"
        }

        let lastCol = columnName(headers.count - 1)
        let lastRow = records.count + 1
        let drawing = includesImages
            ? "<drawing r:id=\"rId1\"/>"
            : ""

        var cols = """
        <cols>
          <col min="1" max="1" width="6" customWidth="1"/>
          <col min="2" max="2" width="42" customWidth="1"/>
          <col min="3" max="3" width="16" customWidth="1"/>
          <col min="4" max="4" width="10" customWidth="1"/>
          <col min="5" max="5" width="14" customWidth="1"/>
          <col min="6" max="6" width="22" customWidth="1"/>
          <col min="7" max="7" width="10" customWidth="1"/>
        """
        if includesImages {
            cols += "<col min=\"8\" max=\"8\" width=\"16\" customWidth=\"1\"/>"
        }
        cols += "</cols>"

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        \(cols)
        <dimension ref="A1:\(lastCol)\(lastRow)"/>
        <sheetData>
        \(rowsXML)
        </sheetData>
        \(drawing)
        </worksheet>
        """
    }

    private var sheetRels: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>
        </Relationships>
        """
    }

    private var drawingXML: String {
        var anchors = ""
        var pictureID = 1
        var relationshipIndex = 0
        // ~72pt square in EMUs (English Metric Units: 914400 = 1 inch).
        let sizeEMUs = 914400

        for (index, png) in images.enumerated() {
            guard png != nil else { continue }
            relationshipIndex += 1
            pictureID += 1
            // SpreadsheetDrawing rows are 0-based; row 0 is the header.
            let row = index + 1
            anchors += """
            <xdr:oneCellAnchor>
              <xdr:from>
                <xdr:col>7</xdr:col>
                <xdr:colOff>95250</xdr:colOff>
                <xdr:row>\(row)</xdr:row>
                <xdr:rowOff>95250</xdr:rowOff>
              </xdr:from>
              <xdr:ext cx="\(sizeEMUs)" cy="\(sizeEMUs)"/>
              <xdr:pic>
                <xdr:nvPicPr>
                  <xdr:cNvPr id="\(pictureID)" name="QR \(index + 1)" descr="QR code \(index + 1)"/>
                  <xdr:cNvPicPr>
                    <a:picLocks noChangeAspect="1"/>
                  </xdr:cNvPicPr>
                </xdr:nvPicPr>
                <xdr:blipFill>
                  <a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rId\(relationshipIndex)" cstate="print"/>
                  <a:stretch><a:fillRect/></a:stretch>
                </xdr:blipFill>
                <xdr:spPr bwMode="auto">
                  <a:xfrm>
                    <a:off x="0" y="0"/>
                    <a:ext cx="\(sizeEMUs)" cy="\(sizeEMUs)"/>
                  </a:xfrm>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                  <a:ln w="9525"><a:noFill/></a:ln>
                </xdr:spPr>
              </xdr:pic>
              <xdr:clientData/>
            </xdr:oneCellAnchor>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        \(anchors)
        </xdr:wsDr>
        """
    }

    private var drawingRels: String {
        var relationships = ""
        var relationshipIndex = 0
        for png in images {
            guard png != nil else { continue }
            relationshipIndex += 1
            relationships += """
            <Relationship Id="rId\(relationshipIndex)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image\(relationshipIndex).png"/>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(relationships)
        </Relationships>
        """
    }

    private func inlineCell(column: Int, row: Int, text: String, style: Int) -> String {
        let ref = "\(columnName(column))\(row)"
        return "<c r=\"\(ref)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(text))</t></is></c>"
    }

    private func columnName(_ index: Int) -> String {
        var value = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(65 + value % 26)!) + name
            value = value / 26 - 1
        } while value >= 0
        return name
    }

    private func xmlEscape(_ value: String) -> String {
        let cleaned = String(value.unicodeScalars.filter { scalar in
            let code = scalar.value
            return code == 0x9 || code == 0xA || code == 0xD || code >= 0x20
        })
        return cleaned
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
// MARK: - ZIP (STORE)

private enum ZipStoreArchive {

    static func write(entries: [(path: String, data: Data)], to url: URL) throws {
        try data(from: entries).write(to: url, options: .atomic)
    }

    static func data(from entries: [(path: String, data: Data)]) throws -> Data {
        var localFiles = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let nameLength = UInt16(nameData.count)

            var local = Data()
            local.appendUInt32(0x04034b50)
            local.appendUInt16(20)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(nameLength)
            local.appendUInt16(0)
            local.append(nameData)
            local.append(entry.data)

            var central = Data()
            central.appendUInt32(0x02014b50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(nameLength)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(offset)
            central.append(nameData)

            offset += UInt32(local.count)
            localFiles.append(local)
            centralDirectory.append(central)
        }

        var end = Data()
        end.appendUInt32(0x06054b50)
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt32(UInt32(centralDirectory.count))
        end.appendUInt32(offset)
        end.appendUInt16(0)

        return localFiles + centralDirectory + end
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            let pointer = buffer.bindMemory(to: UInt8.self).baseAddress
            return UInt32(zlib.crc32(0, pointer, uInt(buffer.count)))
        }
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: 2))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: 4))
    }
}
