import CoreTransferable
import UniformTypeIdentifiers

/// Lightweight ShareLink payloads. File bytes are built only when the system
/// actually exports (`FileRepresentation`), not when the share menu appears.

struct HistoryTextFileExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in
            try await deferredFile {
                HistoryExporter().writeText(item.records)
            }
        }
    }
}

struct HistoryCSVExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            try await deferredFile {
                HistoryExporter().writeCSV(item.records)
            }
        }
    }
}

struct HistoryCSVPackageExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { item in
            try await deferredFile {
                HistoryExporter().writeCSVPackage(item.records)
            }
        }
    }
}

struct HistoryExcelExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]
    let withImages: Bool

    private static var xlsxType: UTType {
        UTType(mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
            ?? UTType(filenameExtension: "xlsx")
            ?? .data
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: xlsxType) { item in
            try await deferredFile {
                item.withImages
                    ? HistoryExporter().writeExcelWithImages(item.records)
                    : HistoryExporter().writeExcel(item.records)
            }
        }
    }
}

struct HistoryJSONExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            try await deferredFile {
                HistoryExporter().writeJSON(item.records)
            }
        }
    }
}

struct HistoryPDFExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]
    let withImages: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            try await deferredFile {
                item.withImages
                    ? HistoryExporter().writePDFWithImages(item.records)
                    : HistoryExporter().writePDF(item.records)
            }
        }
    }
}

private func deferredFile(_ build: @escaping @MainActor () -> URL?) async throws -> SentTransferredFile {
    let url = try await MainActor.run {
        guard let url = build() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
    return SentTransferredFile(url, allowAccessingOriginalFile: true)
}
