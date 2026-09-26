import SwiftUI
import SwiftData

private enum HistoryFavoritesFilter: String, CaseIterable, Identifiable {
    case all, favoritesOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Show all"
        case .favoritesOnly: return "Show favorites"
        }
    }
}

private enum HistorySortOrder: String, CaseIterable, Identifiable {
    case newest, oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        }
    }
}

private enum HistoryTypeFilter: String, CaseIterable, Identifiable {
    case all, website, wifi, contact, email, sms, location, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All types"
        case .website: return "Websites"
        case .wifi: return "Wi-Fi"
        case .contact: return "Contacts"
        case .email: return "Email"
        case .sms: return "SMS"
        case .location: return "Locations"
        case .text: return "Text"
        }
    }

    func matches(_ content: ScannedContent) -> Bool {
        switch (self, content) {
        case (.all, _), (.website, .website), (.wifi, .wifi), (.contact, .contact),
             (.email, .email), (.sms, .sms), (.location, .location), (.text, .text):
            return true
        default:
            return false
        }
    }
}

private let historyExportProgressScrollID = "history-export-progress"

struct HistoryView: View {

    @State private var favoritesFilter: HistoryFavoritesFilter = .all
    @State private var typeFilter: HistoryTypeFilter = .all
    @State private var sortOrder: HistorySortOrder = .newest
    @State private var searchText = ""
    @State private var isEditing = false
    @State private var selectedCodeID: PersistentIdentifier?
    @State private var bulkSelection = Set<PersistentIdentifier>()
    @State private var toast: String?
    @State private var confirmDelete = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        HistoryViewContent(
            favoritesOnly: favoritesFilter == .favoritesOnly,
            newestFirst: sortOrder == .newest,
            favoritesFilter: $favoritesFilter,
            typeFilter: $typeFilter,
            sortOrder: $sortOrder,
            searchText: $searchText,
            isEditing: $isEditing,
            selectedCodeID: $selectedCodeID,
            bulkSelection: $bulkSelection,
            toast: $toast,
            confirmDelete: $confirmDelete,
            columnVisibility: $columnVisibility
        )
    }
}

/// Owns the SwiftData `@Query` so favorites / sort can use `#Predicate` and store order.
private struct HistoryViewContent: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [CodeRecord]

    @Binding var favoritesFilter: HistoryFavoritesFilter
    @Binding var typeFilter: HistoryTypeFilter
    @Binding var sortOrder: HistorySortOrder
    @Binding var searchText: String
    @Binding var isEditing: Bool
    @Binding var selectedCodeID: PersistentIdentifier?
    @Binding var bulkSelection: Set<PersistentIdentifier>
    @Binding var toast: String?
    @Binding var confirmDelete: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @State private var isExporting = false
    @State private var exportPercent = 0
    @State private var preparedExport: PreparedHistoryExport?
    @State private var exportTask: Task<Void, Never>?
    @State private var isOrganizing = false
    @State private var organizeTask: Task<Void, Never>?

    private let parser = ScannedContentParser()
    private let safety = LinkSafety()
    private let clipboard = Clipboard()

    init(
        favoritesOnly: Bool,
        newestFirst: Bool,
        favoritesFilter: Binding<HistoryFavoritesFilter>,
        typeFilter: Binding<HistoryTypeFilter>,
        sortOrder: Binding<HistorySortOrder>,
        searchText: Binding<String>,
        isEditing: Binding<Bool>,
        selectedCodeID: Binding<PersistentIdentifier?>,
        bulkSelection: Binding<Set<PersistentIdentifier>>,
        toast: Binding<String?>,
        confirmDelete: Binding<Bool>,
        columnVisibility: Binding<NavigationSplitViewVisibility>
    ) {
        let order: SortOrder = newestFirst ? .reverse : .forward
        if favoritesOnly {
            _records = Query(
                filter: #Predicate<CodeRecord> { $0.isFavorite == true },
                sort: \CodeRecord.createdAt,
                order: order
            )
        } else {
            _records = Query(sort: \CodeRecord.createdAt, order: order)
        }
        _favoritesFilter = favoritesFilter
        _typeFilter = typeFilter
        _sortOrder = sortOrder
        _searchText = searchText
        _isEditing = isEditing
        _selectedCodeID = selectedCodeID
        _bulkSelection = bulkSelection
        _toast = toast
        _confirmDelete = confirmDelete
        _columnVisibility = columnVisibility
    }

    private var shown: [CodeRecord] {
        records.filter { record in
            if !searchText.isEmpty,
               !record.value.localizedCaseInsensitiveContains(searchText),
               !record.symbology.localizedCaseInsensitiveContains(searchText) {
                return false
            }

            guard typeFilter != .all else { return true }
            return typeFilter.matches(parser.parse(record.value))
        }
    }

    private var shownIDs: [PersistentIdentifier] {
        shown.map(\.persistentModelID)
    }

    private var hasNonDefaultFilters: Bool {
        typeFilter != .all || favoritesFilter == .favoritesOnly || sortOrder != .newest
    }

    private var hasSmartOrganization: Bool {
        records.contains { $0.isSmartOrganized }
    }

    private var smartSections: [HistorySmartSection]? {
        guard hasSmartOrganization else { return nil }

        var buckets: [String: [CodeRecord]] = [:]
        var order: [String] = []

        for record in shown {
            let key = record.isSmartOrganized ? record.smartGroupTitle : "Uncategorized"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key, default: []].append(record)
        }

        // Keep model group order; park Uncategorized at the end.
        order.sort { lhs, rhs in
            if lhs == "Uncategorized" { return false }
            if rhs == "Uncategorized" { return true }
            let left = buckets[lhs]?.map(\.smartSortIndex).min() ?? Int.max
            let right = buckets[rhs]?.map(\.smartSortIndex).min() ?? Int.max
            if left != right { return left < right }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        return order.compactMap { title in
            guard var items = buckets[title], !items.isEmpty else { return nil }
            items.sort {
                if $0.smartSortIndex != $1.smartSortIndex {
                    return $0.smartSortIndex < $1.smartSortIndex
                }
                return $0.createdAt > $1.createdAt
            }
            return HistorySmartSection(id: title, title: title, records: items)
        }
    }

    private var selectedRecord: CodeRecord? {
        guard let selectedCodeID else { return nil }
        return records.first { $0.persistentModelID == selectedCodeID }
    }

    private var selectedRecords: [CodeRecord] {
        shown.filter { bulkSelection.contains($0.persistentModelID) }
    }

    private var runsOnMac: Bool {
        #if os(macOS)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    var body: some View {
        #if os(macOS)
        macHistoryBody
        #else
        iosHistoryBody
        #endif
    }

    #if os(macOS)
    /// Tab sidebar stays owned by `TabView`; this is list | detail only (no nested split sidebar).
    private var macHistoryBody: some View {
        HStack(spacing: 0) {
            NavigationStack {
                historySidebar
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

            Divider()

            NavigationStack {
                historyDetail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            TransientToastOverlay(message: toast)
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .alert(deleteAlertTitle, isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .historyExportShare(preparedExport: $preparedExport) {
            withAnimation(.snappy) {
                isExporting = false
            }
        }
        .onChange(of: shownIDs) { _, visibleIDs in
            Task { @MainActor in
                if let selectedCodeID, !visibleIDs.contains(selectedCodeID) {
                    self.selectedCodeID = nil
                }
                bulkSelection = bulkSelection.filter { visibleIDs.contains($0) }
            }
        }
    }
    #endif

    #if !os(macOS)
    private var iosHistoryBody: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            historySidebar
        } detail: {
            NavigationStack {
                historyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .bottom) {
            TransientToastOverlay(message: toast)
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .alert(deleteAlertTitle, isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .historyExportShare(preparedExport: $preparedExport) {
            withAnimation(.snappy) {
                isExporting = false
            }
        }
        .onChange(of: shownIDs) { _, visibleIDs in
            Task { @MainActor in
                if let selectedCodeID, !visibleIDs.contains(selectedCodeID) {
                    self.selectedCodeID = nil
                }
                bulkSelection = bulkSelection.filter { visibleIDs.contains($0) }
            }
        }
        .onChange(of: selectedCodeID) { _, _ in
            columnVisibility = .all
        }
    }
    #endif

    private var historySidebar: some View {
        historyList
            .navigationTitle(isEditing ? selectionTitle : "History")
            #if os(macOS)
            .toolbarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search codes")
            .listStyle(.sidebar)
            #else
            .toolbarTitleDisplayMode(isEditing ? .inline : .inlineLarge)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search codes")
            .environment(\.editMode, Binding(
                get: { isEditing ? .active : .inactive },
                set: { isEditing = $0.isEditing }
            ))
            #endif
            .toolbar { toolbarContent }
            .overlay {
                if shown.isEmpty {
                    emptyState
                }
            }
    }

    @ViewBuilder
    private var historyList: some View {
        #if os(macOS)
        macHistoryList
        #else
        iosHistoryList
        #endif
    }

    #if os(macOS)
    /// One stable `List` so Select/Done can animate like iOS EditMode (no remount).
    private var macHistoryList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedCodeID) {
                exportProgressSection
                historyRecordRows(preferContextMenuOnly: true, macBulkSelect: true)
            }
            .id("history-mac")
            .selectionDisabled(isEditing)
            .animation(.snappy, value: isEditing)
            .animation(.snappy, value: bulkSelection)
            .animation(.snappy, value: isExporting)
            .animation(.snappy, value: hasSmartOrganization)
            .scrollExportProgressIntoView(proxy: proxy, isExporting: isExporting)
        }
    }
    #endif

    #if !os(macOS)
    private var iosHistoryList: some View {
        ScrollViewReader { proxy in
            if isEditing {
                List(selection: $bulkSelection) {
                    exportProgressSection
                    historyRecordRows(preferContextMenuOnly: false, macBulkSelect: false)
                }
                .id("history-bulk")
                .animation(.snappy, value: isExporting)
                .animation(.snappy, value: hasSmartOrganization)
                .scrollExportProgressIntoView(proxy: proxy, isExporting: isExporting)
            } else {
                List(selection: $selectedCodeID) {
                    exportProgressSection
                    historyRecordRows(preferContextMenuOnly: false, macBulkSelect: false)
                }
                .id("history-single")
                .animation(.snappy, value: isExporting)
                .animation(.snappy, value: hasSmartOrganization)
                .scrollExportProgressIntoView(proxy: proxy, isExporting: isExporting)
            }
        }
    }
    #endif

    @ViewBuilder
    private func historyRecordRows(preferContextMenuOnly: Bool, macBulkSelect: Bool) -> some View {
        if let sections = smartSections {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.records, id: \.persistentModelID) { record in
                        historyRowEntry(
                            for: record,
                            preferContextMenuOnly: preferContextMenuOnly,
                            macBulkSelect: macBulkSelect
                        )
                    }
                }
            }
        } else {
            ForEach(shown, id: \.persistentModelID) { record in
                historyRowEntry(
                    for: record,
                    preferContextMenuOnly: preferContextMenuOnly,
                    macBulkSelect: macBulkSelect
                )
            }
        }
    }

    @ViewBuilder
    private func historyRowEntry(
        for record: CodeRecord,
        preferContextMenuOnly: Bool,
        macBulkSelect: Bool
    ) -> some View {
        Group {
            if macBulkSelect && isEditing {
                row(for: record)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleBulkSelection(record.persistentModelID)
                    }
            } else {
                row(for: record)
                    .tag(record.persistentModelID)
            }
        }
        .historyRowActions(
            favorite: { record.isFavorite.toggle() },
            isFavorite: record.isFavorite,
            delete: { delete(record) },
            preferContextMenuOnly: preferContextMenuOnly
        )
    }

    @ViewBuilder
    private var exportProgressSection: some View {
        if isExporting {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Exporting…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Text("\(exportPercent)%")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText())
                            .accessibilityLabel("\(exportPercent) percent")
                    }

                    ProgressView(value: Double(exportPercent), total: 100)
                }
                .padding(.vertical, 4)
                .animation(.snappy, value: exportPercent)
                .accessibilityElement(children: .combine)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(historyExportProgressScrollID)
        }
    }

    @ViewBuilder
    private var historyDetail: some View {
        Group {
            if isEditing {
                ContentUnavailableView(
                    "Selecting codes",
                    systemImage: "checkmark.circle",
                    description: Text(runsOnMac
                                      ? "Tap the circles in the list, then copy, share or delete."
                                      : "Choose codes in the list, then copy, share or delete.")
                )
                .navigationTitle("History")
                .toolbarTitleDisplayMode(.inline)
            } else if let selectedRecord {
                CodeDetailView(record: selectedRecord)
                    .id(selectedRecord.persistentModelID)
            } else {
                ContentUnavailableView(
                    "Select a Code",
                    systemImage: "qrcode",
                    description: Text("Choose a code from the list to see its details.")
                )
                .navigationTitle("Details")
                .toolbarTitleDisplayMode(.inline)
            }
        }
        .animation(.snappy, value: isEditing)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if favoritesFilter == .favoritesOnly {
            ContentUnavailableView(
                "No favorites",
                systemImage: "star",
                description: Text(runsOnMac
                                  ? "Control-click a row to star it."
                                  : "Swipe a row to the right to star it.")
            )
        } else if typeFilter != .all {
            ContentUnavailableView("No \(typeFilter.title.lowercased())",
                                   systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text("Nothing in your history matches this filter."))
        } else {
            ContentUnavailableView("Nothing yet", systemImage: "clock",
                                   description: Text("Codes you scan or create show up here."))
        }
    }

    private func row(for record: CodeRecord) -> some View {
        let content = parser.parse(record.value)
        let isFlaggedWebsite: Bool = {
            guard case .website(let url) = content else { return false }
            return !safety.warnings(for: url).isEmpty
        }()
        let isBulkSelected = bulkSelection.contains(record.persistentModelID)

        return HStack(spacing: 12) {
            if runsOnMac && isEditing {
                // Match iOS EditMode: blue filled circle + white check (readable on any row tint).
                Image(systemName: isBulkSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .fontWeight(.regular)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isBulkSelected ? Color.white : Color.secondary.opacity(0.45),
                        isBulkSelected ? Color.accentColor : Color.clear
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(isBulkSelected ? "Selected" : "Not selected")
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            Image(systemName: content.icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.listTitle)
                    .lineLimit(1)

                if record.isSmartOrganized, record.listTitle != record.value {
                    Text(record.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(record.createdAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if isFlaggedWebsite {
                    Image(systemName: "exclamationmark.shield.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .orange)
                        .accessibilityLabel("Link warning")
                }

                if record.isFavorite {
                    Image(systemName: "star.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.yellow.gradient)
                        .accessibilityLabel("Favorite")
                }
            }
        }
        .padding(.leading, runsOnMac && isEditing ? 2 : 0)
        .animation(.snappy, value: isEditing)
        .animation(.snappy, value: isBulkSelected)
    }

    private func toggleBulkSelection(_ id: PersistentIdentifier) {
        withAnimation(.snappy) {
            if bulkSelection.contains(id) {
                bulkSelection.remove(id)
            } else {
                bulkSelection.insert(id)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: PlatformToolbar.leading) {
            selectButton
        }

        if isEditing {
            ToolbarItem(placement: PlatformToolbar.trailing) { deleteSelectedButton }
            ToolbarItem(placement: PlatformToolbar.trailing) { copySelectedButton }
            ToolbarItem(placement: PlatformToolbar.trailing) { shareSelectedButton }
        } else {
            ToolbarItem { filterMenu }
        }
    }

    private var selectButton: some View {
        Button {
            withAnimation(.snappy) {
                if isEditing {
                    isEditing = false
                    bulkSelection.removeAll()
                } else {
                    isEditing = true
                    bulkSelection.removeAll()
                    selectedCodeID = nil
                }
            }
        } label: {
            if isEditing {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Done")
            } else {
                Text("Select")
            }
        }
        .disabled(shown.isEmpty && !isEditing)
        .modifier(HistorySelectToolbarStyle(isDone: isEditing))
        .animation(.snappy, value: isEditing)
    }

    private var deleteSelectedButton: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            #if os(macOS)
            Label("Delete", systemImage: "trash")
            #else
            Image(systemName: "trash")
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            #endif
        }
        #if !os(macOS)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(.red)
        .accessibilityLabel("Delete")
        #endif
        .disabled(bulkSelection.isEmpty)
    }

    private var copySelectedButton: some View {
        Button {
            copySelected()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(bulkSelection.isEmpty)
    }

    private var shareSelectedButton: some View {
        Menu {
            ShareLink(item: sharedText) {
                Label("Share as text", systemImage: "text.alignleft")
            }

            Button {
                startExport(.textFile)
            } label: {
                Label("Export as text file", systemImage: "doc.text")
            }

            Menu {
                Button {
                    startExport(.csvPackage)
                } label: {
                    Label("With images", systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    startExport(.csv)
                } label: {
                    Label("Without images", systemImage: "text.menu")
                }
            } label: {
                Label("Export as CSV", systemImage: "text.rectangle")
            }

            Menu {
                Button {
                    startExport(.excel(withImages: true))
                } label: {
                    Label("With embedded images", systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    startExport(.excel(withImages: false))
                } label: {
                    Label("Without images", systemImage: "text.menu")
                }
            } label: {
                Label("Export as Excel", systemImage: "tablecells")
            }

            Button {
                startExport(.json)
            } label: {
                Label("Export as JSON", systemImage: "curlybraces")
            }

            Menu {
                Button {
                    startExport(.pdf(withImages: true))
                } label: {
                    Label("With images", systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    startExport(.pdf(withImages: false))
                } label: {
                    Label("Without images", systemImage: "text.menu")
                }
            } label: {
                Label("Export as PDF", systemImage: "doc.richtext")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(bulkSelection.isEmpty || isExporting)
    }

    private func startExport(_ kind: HistoryExportKind) {
        guard !isExporting else { return }
        let records = selectedRecords
        guard !records.isEmpty else { return }

        exportTask?.cancel()
        withAnimation(.snappy) {
            isExporting = true
            exportPercent = 0
        }

        exportTask = Task { @MainActor in
            let exporter = HistoryExporter()
            let onProgress: @MainActor (Double) -> Void = { value in
                let percent = Int((value * 100).rounded(.down))
                withAnimation(.snappy) {
                    exportPercent = min(max(percent, 0), 100)
                }
            }

            let url: URL?
            switch kind {
            case .textFile:
                url = await exporter.writeText(records, progress: onProgress)
            case .csv:
                url = await exporter.writeCSV(records, progress: onProgress)
            case .csvPackage:
                url = await exporter.writeCSVPackage(records, progress: onProgress)
            case .excel(let withImages):
                url = withImages
                    ? await exporter.writeExcelWithImages(records, progress: onProgress)
                    : await exporter.writeExcel(records, progress: onProgress)
            case .json:
                url = await exporter.writeJSON(records, progress: onProgress)
            case .pdf(let withImages):
                url = withImages
                    ? await exporter.writePDFWithImages(records, progress: onProgress)
                    : await exporter.writePDF(records, progress: onProgress)
            }

            guard !Task.isCancelled else { return }

            if let url {
                withAnimation(.snappy) {
                    exportPercent = 100
                }
                await Task.yield()
                // Keep the 100% row visible until the system share UI appears.
                preparedExport = PreparedHistoryExport(url: url)
            } else {
                withAnimation(.snappy) {
                    isExporting = false
                }
                show("Couldn't export")
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            if runsOnMac {
                macFilterSections
            } else {
                HistoryTypeFilterSubmenu(selection: $typeFilter)
                HistorySortSubmenu(selection: $sortOrder)
                HistoryFavoritesSubmenu(selection: $favoritesFilter)
            }

            if HistorySmartOrganizer.isAvailable {
                Divider()

                if hasSmartOrganization {
                    Button {
                        organizeCodesIntelligently()
                    } label: {
                        Label("Reorganize all codes", systemImage: "sparkles")
                    }
                    .disabled(records.isEmpty || isOrganizing)

                    Button("Clear smart organization", role: .destructive) {
                        clearSmartOrganization()
                    }
                    .disabled(isOrganizing)
                } else {
                    Button {
                        organizeCodesIntelligently()
                    } label: {
                        Label("Organize codes intelligently", systemImage: "sparkles")
                    }
                    .disabled(records.isEmpty || isOrganizing)
                }
            }

            if hasNonDefaultFilters {
                Divider()

                Button("Reset filters", role: .destructive) {
                    withAnimation(.smooth(duration: 0.35)) {
                        resetFilters()
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: filterMenuSymbol)
        }
        .tint((hasNonDefaultFilters || hasSmartOrganization) ? Color.accentColor : Color.primary)
        .help("Filter and sort history")
    }

    private var filterMenuSymbol: String {
        if isOrganizing {
            return "sparkles"
        }
        if hasNonDefaultFilters || hasSmartOrganization {
            return "line.3.horizontal.decrease.circle.fill"
        }
        return "line.3.horizontal.decrease.circle"
    }

    private func organizeCodesIntelligently() {
        guard HistorySmartOrganizer.isAvailable, !isOrganizing else { return }

        organizeTask?.cancel()
        isOrganizing = true
        show("Organizing with Apple Intelligence…")

        organizeTask = Task { @MainActor in
            do {
                let descriptor = FetchDescriptor<CodeRecord>(
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                let allRecords = try modelContext.fetch(descriptor)
                guard !allRecords.isEmpty else {
                    isOrganizing = false
                    show("Nothing to organize")
                    return
                }

                let inputs: [HistorySmartOrganizer.CodeInput] = allRecords.enumerated().map { index, record in
                    let content = parser.parse(record.value)
                    return HistorySmartOrganizer.CodeInput(
                        id: index + 1,
                        typeTitle: content.title,
                        value: record.value,
                        kind: record.kind == .created ? "created" : "scanned",
                        nearbyHints: record.nearbyContext.map { field in
                            field.label.isEmpty ? field.value : "\(field.label): \(field.value)"
                        }.filter { !$0.isEmpty }
                    )
                }

                let organization = try await HistorySmartOrganizer.organize(inputs)
                guard !Task.isCancelled else {
                    isOrganizing = false
                    return
                }

                let byID = Dictionary(
                    organization.assignments.map { ($0.id, $0) },
                    uniquingKeysWith: { _, latest in latest }
                )
                for (index, record) in allRecords.enumerated() {
                    let id = index + 1
                    if let assignment = byID[id] {
                        record.smartGroupTitle = assignment.groupTitle
                        record.smartTitle = assignment.smartTitle
                        record.smartSortIndex = index
                    } else {
                        record.smartGroupTitle = "Other"
                        record.smartTitle = String(record.value.prefix(40))
                        record.smartSortIndex = index
                    }
                }

                try? modelContext.save()
                withAnimation(.snappy) {
                    isOrganizing = false
                }
                let groupCount = Set(organization.assignments.map(\.groupTitle)).count
                show(groupCount == 1
                     ? "Organized into 1 group"
                     : "Organized into \(groupCount) groups")
            } catch {
                isOrganizing = false
                show(error.localizedDescription)
            }
        }
    }

    private func clearSmartOrganization() {
        organizeTask?.cancel()
        withAnimation(.snappy) {
            for record in records {
                record.smartGroupTitle = ""
                record.smartTitle = ""
                record.smartSortIndex = 0
            }
            isOrganizing = false
        }
        try? modelContext.save()
        show("Smart organization cleared")
    }

    @ViewBuilder
    private var macFilterSections: some View {
        Picker("QR Type", selection: $typeFilter) {
            ForEach(HistoryTypeFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }

        Picker("Sort", selection: $sortOrder) {
            ForEach(HistorySortOrder.allCases) { order in
                Text(order.title).tag(order)
            }
        }

        Picker("Favorites", selection: $favoritesFilter) {
            ForEach(HistoryFavoritesFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
    }

    private func resetFilters() {
        typeFilter = .all
        favoritesFilter = .all
        sortOrder = .newest
    }

    private func delete(_ record: CodeRecord) {
        let id = record.persistentModelID
        if selectedCodeID == id { selectedCodeID = nil }
        bulkSelection.remove(id)
        modelContext.delete(record)
    }

    private func deleteSelected() {
        let doomed = selectedRecords
        let doomedIDs = Set(doomed.map(\.persistentModelID))
        if let selectedCodeID, doomedIDs.contains(selectedCodeID) {
            self.selectedCodeID = nil
        }
        bulkSelection.subtract(doomedIDs)
        for record in doomed {
            modelContext.delete(record)
        }
    }

    private func show(_ message: String) {
        TransientMessage.present($toast, text: message)
    }

    private func copySelected() {
        let count = bulkSelection.count
        clipboard.copy(text: sharedText)
        finishSelecting()
        show(count == 1 ? "Code copied" : "\(count) codes copied")
    }

    private func finishSelecting() {
        withAnimation(.snappy) {
            bulkSelection.removeAll()
            isEditing = false
        }
    }

    private var deleteAlertTitle: String {
        bulkSelection.count == 1 ? "Delete this code?" : "Delete \(bulkSelection.count) codes?"
    }

    private var selectionTitle: String {
        bulkSelection.isEmpty ? "Select codes" : "\(bulkSelection.count) selected"
    }

    private var sharedText: String {
        HistoryExporter().plainText(selectedRecords)
    }
}

private enum HistoryExportKind {
    case textFile
    case csv
    case csvPackage
    case excel(withImages: Bool)
    case json
    case pdf(withImages: Bool)
}

private struct HistorySmartSection: Identifiable {
    let id: String
    let title: String
    let records: [CodeRecord]
}

private struct PreparedHistoryExport: Identifiable {
    let id = UUID()
    let url: URL
}

private extension View {
    func historyExportShare(
        preparedExport: Binding<PreparedHistoryExport?>,
        onSharePresented: @escaping () -> Void
    ) -> some View {
        background(alignment: .topTrailing) {
            if let item = preparedExport.wrappedValue {
                PlatformFileShareSheet(
                    url: item.url,
                    isPresented: Binding(
                        get: { preparedExport.wrappedValue != nil },
                        set: { if !$0 { preparedExport.wrappedValue = nil } }
                    ),
                    onPresented: onSharePresented
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    func scrollExportProgressIntoView(proxy: ScrollViewProxy, isExporting: Bool) -> some View {
        onChange(of: isExporting) { _, exporting in
            guard exporting else { return }
            Task { @MainActor in
                // Let the progress section enter the list hierarchy first.
                await Task.yield()
                withAnimation(.snappy) {
                    proxy.scrollTo(historyExportProgressScrollID, anchor: .top)
                }
            }
        }
    }
}

private struct HistorySelectToolbarStyle: ViewModifier {
    let isDone: Bool

    func body(content: Content) -> some View {
        if isDone {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.green)
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func historyRowActions(
        favorite: @escaping () -> Void,
        isFavorite: Bool,
        delete: @escaping () -> Void,
        preferContextMenuOnly: Bool = false
    ) -> some View {
        if preferContextMenuOnly {
            self.contextMenu {
                Button(action: favorite) {
                    Label(isFavorite ? "Remove from favorites" : "Add to favorites",
                          systemImage: isFavorite ? "star.slash" : "star")
                }
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            }
        } else {
            self
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive, action: delete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button(action: favorite) {
                        Label(isFavorite ? "Unfavorite" : "Favorite",
                              systemImage: isFavorite ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
                .contextMenu {
                    Button(action: favorite) {
                        Label(isFavorite ? "Remove from favorites" : "Add to favorites",
                              systemImage: isFavorite ? "star.slash" : "star")
                    }
                    Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                }
        }
    }
}

private struct HistoryTypeFilterSubmenu: View {

    @Binding var selection: HistoryTypeFilter

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(HistoryTypeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("QR Type")
            } icon: {
                Image(systemName: "qrcode")
            }
            Text(selection.title)
        }
    }
}

private struct HistorySortSubmenu: View {

    @Binding var selection: HistorySortOrder

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(HistorySortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("Sort")
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            Text(selection.title)
        }
    }
}

private struct HistoryFavoritesSubmenu: View {

    @Binding var selection: HistoryFavoritesFilter

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(HistoryFavoritesFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("Favorites")
            } icon: {
                Image(systemName: "star")
            }
            Text(selection.title)
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: CodeRecord.self, inMemory: true)
}
