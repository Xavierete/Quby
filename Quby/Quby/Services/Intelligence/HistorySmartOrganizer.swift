import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Apple Intelligence organizer for History (Foundation Models).
///
/// Flow:
/// 1. Check `isAvailable` (device supports Apple Intelligence + model ready).
/// 2. Convert SwiftData records into numbered `CodeInput` snapshots.
/// 3. Ask the system language model for grouped sections + short row titles.
/// 4. Map the structured `@Generable` result back onto each `CodeRecord`.
enum HistorySmartOrganizer {

    /// Plain snapshot sent to the model (Sendable; no SwiftData / MainActor types).
    struct CodeInput: Sendable {
        /// 1-based id the model must echo back exactly.
        let id: Int
        let typeTitle: String
        let value: String
        let kind: String
        /// Optional OCR / nearby context hints from the scan frame.
        let nearbyHints: [String]
    }

    /// One code placed into a named group with a display title.
    struct CodeAssignment: Sendable {
        let id: Int
        let groupTitle: String
        let smartTitle: String
    }

    /// Full organization result for the requested batch.
    struct Organization: Sendable {
        let assignments: [CodeAssignment]
    }

    enum OrganizerError: LocalizedError {
        case unavailable
        case empty
        case incomplete

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Intelligence isn’t available on this device."
            case .empty:
                return "Nothing to organize."
            case .incomplete:
                return "Couldn’t organize every code. Try again."
            }
        }
    }

    /// `true` only when the system on-device model is ready to run.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        SystemLanguageModel.default.isAvailable
        #else
        false
        #endif
    }

    /// Organizes codes into groups. Large lists are split into chunks so each
    /// prompt stays within the on-device context window.
    static func organize(_ codes: [CodeInput]) async throws -> Organization {
        guard isAvailable else { throw OrganizerError.unavailable }
        guard !codes.isEmpty else { throw OrganizerError.empty }

        #if canImport(FoundationModels)
        var assignments: [CodeAssignment] = []
        // Keep prompts small enough for the on-device context window.
        let chunkSize = 28
        for chunkStart in stride(from: 0, to: codes.count, by: chunkSize) {
            let end = min(chunkStart + chunkSize, codes.count)
            let chunk = Array(codes[chunkStart..<end])
            let partial = try await organizeChunk(chunk)
            assignments.append(contentsOf: partial)
        }

        // Every input id must appear exactly once across all chunk results.
        let expected = Set(codes.map(\.id))
        let got = Set(assignments.map(\.id))
        guard expected == got else { throw OrganizerError.incomplete }
        return Organization(assignments: assignments)
        #else
        throw OrganizerError.unavailable
        #endif
    }

    #if canImport(FoundationModels)
    // MARK: - Guided generation schema
    // `@Generable` + `@Guide` tell Foundation Models the exact Swift shape to return
    // (no brittle hand-parsed JSON).

    @Generable(description: "Smart grouping of QR and barcode history items.")
    struct ModelResult {
        @Guide(description: "Named groups of related codes. Use short, clear titles.")
        var groups: [ModelGroup]
    }

    @Generable(description: "One named group of codes.")
    struct ModelGroup {
        @Guide(description: "Short section title, for example Travel, Home Wi-Fi, Social links.")
        var title: String

        @Guide(description: "Codes that belong in this group.")
        var codes: [ModelCode]
    }

    @Generable(description: "One code placed into a group.")
    struct ModelCode {
        @Guide(description: "Numeric id from the input list. Must match exactly.")
        var id: Int

        @Guide(description: "Short human title for the list row, not the raw payload.")
        var title: String
    }

    /// Runs one LanguageModelSession for a chunk and normalizes the output.
    private static func organizeChunk(_ codes: [CodeInput]) async throws -> [CodeAssignment] {
        let session = LanguageModelSession(
            model: .default,
            instructions: """
            You organize a QR / barcode history list for the Quby app.
            Create a few clear groups with short section titles.
            Give every code a short smart title suitable for a list row.
            Use each numeric id exactly once. Do not invent ids.
            Prefer the person's language when titles are obvious from the payloads.
            Group by meaning (travel, wifi, contacts, shopping, social, work, etc.), not only by technical type.
            """
        )

        // Numbered listing the model uses as the source of truth for ids.
        let listing = codes.map { code in
            var line = "\(code.id). [\(code.typeTitle) · \(code.kind)] \(code.value)"
            if !code.nearbyHints.isEmpty {
                line += " | context: " + code.nearbyHints.joined(separator: "; ")
            }
            return line
        }.joined(separator: "\n")

        let prompt = """
        Organize these codes into smart groups with short titles.
        Return every id exactly once.

        Codes:
        \(listing)
        """

        let response = try await session.respond(
            to: prompt,
            generating: ModelResult.self
        )

        var assignments: [CodeAssignment] = []
        let allowed = Set(codes.map(\.id))

        for group in response.content.groups {
            let groupTitle = cleanedTitle(group.title, fallback: "Other")
            // Ignore any ids the model invents outside this chunk.
            for item in group.codes where allowed.contains(item.id) {
                assignments.append(
                    CodeAssignment(
                        id: item.id,
                        groupTitle: groupTitle,
                        smartTitle: cleanedTitle(item.title, fallback: "Code \(item.id)")
                    )
                )
            }
        }

        // Fill any skipped ids so the chunk is always complete.
        let covered = Set(assignments.map(\.id))
        for code in codes where !covered.contains(code.id) {
            assignments.append(
                CodeAssignment(
                    id: code.id,
                    groupTitle: "Other",
                    smartTitle: shortened(code.value)
                )
            )
        }

        // Drop duplicate ids (keep first).
        var seen = Set<Int>()
        return assignments.filter { seen.insert($0.id).inserted }
    }

    private static func cleanedTitle(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)) + "…"
    }

    private static func shortened(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 40 else { return trimmed }
        return String(trimmed.prefix(37)) + "…"
    }
    #endif
}
