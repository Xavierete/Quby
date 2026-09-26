import CoreGraphics
import CoreText
import Foundation

/// PDF table builder (Core Graphics + Core Text).
struct PDFTableBuilder {

    let records: [CodeRecord]
    let images: [CGImage?]
    let includeImages: Bool
    let parser: ScannedContentParser

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
        let rowHeight = includeImages ? imageRowHeight : textRowHeight
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
        if includeImages {
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
        let line = CTLineCreateWithAttributedString(attributed)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        // PDF contexts use bottom-left origin. Draw with CTLine (no CTM flip),
        // otherwise CTFrame + scale(y: -1) can mirror glyphs.
        context.saveGState()
        context.clip(to: rect)
        context.textMatrix = .identity

        let textHeight = ascent + descent
        let x = rect.minX
        let y = rect.minY + max(0, (rect.height - textHeight) / 2) + descent
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
