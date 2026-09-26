import CoreTransferable
import UniformTypeIdentifiers

/// Lightweight ShareLink payloads. File bytes are built only when the system
/// actually exports (`FileRepresentation`), not when the share menu appears.

struct HistoryTextFileExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in
            try await deferredFile {
                await HistoryExporter().writeText(item.records)
            }
        }
    }
}

struct HistoryCSVExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            try await deferredFile {
                await HistoryExporter().writeCSV(item.records)
            }
        }
    }
}

struct HistoryCSVPackageExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { item in
            try await deferredFile {
                await HistoryExporter().writeCSVPackage(item.records)
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
                if item.withImages {
                    await HistoryExporter().writeExcelWithImages(item.records)
                } else {
                    await HistoryExporter().writeExcel(item.records)
                }
            }
        }
    }
}

struct HistoryJSONExport: Transferable, @unchecked Sendable {
    let records: [CodeRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            try await deferredFile {
                await HistoryExporter().writeJSON(item.records)
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
                if item.withImages {
                    await HistoryExporter().writePDFWithImages(item.records)
                } else {
                    await HistoryExporter().writePDF(item.records)
                }
            }
        }
    }
}

private func deferredFile(_ build: @escaping @MainActor () async -> URL?) async throws -> SentTransferredFile {
    let url = try await Task { @MainActor in
        guard let url = await build() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }.value
    return SentTransferredFile(url, allowAccessingOriginalFile: true)
}
