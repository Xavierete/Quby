import Foundation

/// Builds a schema-friendly `.xlsx` (OOXML / SpreadsheetML).
/// Works with Microsoft Excel, Numbers, and Google Sheets for data rows;
/// embedded QR drawings use DrawingML (`oneCellAnchor` on column H).
struct ExcelWorkbookBuilder {

    let records: [CodeRecord]
    /// One PNG (or `nil`) per record, same order/count as `records`.
    let images: [Data?]
    let includeImages: Bool
    let parser: ScannedContentParser

    /// Column H (0-based index 7) holds QR thumbnails.
    private let qrColumn = 7
    /// ~0.85" square in EMUs (914400 EMUs = 1 inch).
    private let imageSizeEMUs = 777_240
    private let imageInsetEMUs = 95_250

    private var hasEmbeddedImages: Bool {
        includeImages && images.contains { $0 != nil }
    }

    func build() throws -> Data {
        precondition(!includeImages || images.count == records.count)

        var entries: [(path: String, data: Data)] = []

        // OPC requires [Content_Types].xml first.
        entries.append(("[Content_Types].xml", utf8XML(contentTypes)))
        entries.append(("_rels/.rels", utf8XML(rootRels)))
        entries.append(("xl/workbook.xml", utf8XML(workbook)))
        entries.append(("xl/_rels/workbook.xml.rels", utf8XML(workbookRels)))
        entries.append(("xl/styles.xml", utf8XML(styles)))
        entries.append(("xl/worksheets/sheet1.xml", utf8XML(sheetXML)))

        if hasEmbeddedImages {
            entries.append(("xl/worksheets/_rels/sheet1.xml.rels", utf8XML(sheetRels)))
            entries.append(("xl/drawings/drawing1.xml", utf8XML(drawingXML)))
            entries.append(("xl/drawings/_rels/drawing1.xml.rels", utf8XML(drawingRels)))

            var imageIndex = 0
            for png in images {
                guard let png, !png.isEmpty else { continue }
                imageIndex += 1
                entries.append(("xl/media/image\(imageIndex).png", png))
            }
        }

        return try ZipStoreArchive.data(from: entries)
    }

    private func utf8XML(_ string: String) -> Data {
        Data(string.utf8)
    }

    private var contentTypes: String {
        var extras = ""
        if hasEmbeddedImages {
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
        // Minimal but Excel-valid stylesheet (required attributes on xf).
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="2">
            <font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>
            <font><b/><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1">
            <border><left/><right/><top/><bottom/><diagonal/></border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="2">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
          </cellXfs>
          <cellStyles count="1">
            <cellStyle name="Normal" xfId="0" builtinId="0"/>
          </cellStyles>
        </styleSheet>
        """
    }

    private var sheetXML: String {
        let showQRColumn = includeImages
        let headers = ["ID", "Value", "Type", "Kind", "Symbology", "Created", "Favourite"]
            + (showQRColumn ? ["QR"] : [])

        var rowsXML = "<row r=\"1\">"
        for (column, header) in headers.enumerated() {
            rowsXML += inlineCell(column: column, row: 1, text: header, style: 1)
        }
        rowsXML += "</row>"

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for (index, record) in records.enumerated() {
            let row = index + 2
            let height = showQRColumn ? " ht=\"96\" customHeight=\"1\"" : ""
            rowsXML += "<row r=\"\(row)\"\(height) spans=\"1:\(headers.count)\">"
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
        let lastRow = max(1, records.count + 1)
        let drawing = hasEmbeddedImages ? "<drawing r:id=\"rId1\"/>" : ""

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
        if showQRColumn {
            cols += #"<col min="8" max="8" width="14" customWidth="1"/>"#
        }
        cols += "</cols>"

        // Element order matters for SpreadsheetML (dimension → views → format → cols → sheetData → drawing).
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <dimension ref="A1:\(lastCol)\(lastRow)"/>
          <sheetViews>
            <sheetView workbookViewId="0"/>
          </sheetViews>
          <sheetFormatPr defaultRowHeight="15"/>
          \(cols)
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
        var pictureID = 0
        var relationshipIndex = 0

        for (index, png) in images.enumerated() {
            guard let png, !png.isEmpty else { continue }
            relationshipIndex += 1
            pictureID += 1
            // DrawingML rows are 0-based; row 0 is the header → data starts at 1.
            let row = index + 1
            anchors += """
            <xdr:oneCellAnchor>
              <xdr:from>
                <xdr:col>\(qrColumn)</xdr:col>
                <xdr:colOff>\(imageInsetEMUs)</xdr:colOff>
                <xdr:row>\(row)</xdr:row>
                <xdr:rowOff>\(imageInsetEMUs)</xdr:rowOff>
              </xdr:from>
              <xdr:ext cx="\(imageSizeEMUs)" cy="\(imageSizeEMUs)"/>
              <xdr:pic>
                <xdr:nvPicPr>
                  <xdr:cNvPr id="\(pictureID)" name="QR \(index + 1)"/>
                  <xdr:cNvPicPr>
                    <a:picLocks noChangeAspect="1"/>
                  </xdr:cNvPicPr>
                </xdr:nvPicPr>
                <xdr:blipFill>
                  <a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rId\(relationshipIndex)" cstate="print"/>
                  <a:stretch><a:fillRect/></a:stretch>
                </xdr:blipFill>
                <xdr:spPr>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
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
            guard let png, !png.isEmpty else { continue }
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
