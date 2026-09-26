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
        if isEditing {
            if runsOnMac {
                // macOS has no EditMode checkboxes — custom circles + click-to-toggle.
                List {
                    ForEach(shown, id: \.persistentModelID) { record in
                        row(for: record)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleBulkSelection(record.persistentModelID)
                            }
                            .historyRowActions(
                                favorite: { record.isFavorite.toggle() },
                                isFavorite: record.isFavorite,
                                delete: { delete(record) },
                                preferContextMenuOnly: true
                            )
                    }
                }
                .id("history-bulk-mac")
            } else {
                List(selection: $bulkSelection) {
                    ForEach(shown, id: \.persistentModelID) { record in
                        row(for: record)
                            .tag(record.persistentModelID)
                            .historyRowActions(
                                favorite: { record.isFavorite.toggle() },
                                isFavorite: record.isFavorite,
                                delete: { delete(record) },
                                preferContextMenuOnly: false
                            )
                    }
                }
                .id("history-bulk")
            }
        } else {
            List(selection: $selectedCodeID) {
                ForEach(shown, id: \.persistentModelID) { record in
                    row(for: record)
                        .tag(record.persistentModelID)
                        .historyRowActions(
                            favorite: { record.isFavorite.toggle() },
                            isFavorite: record.isFavorite,
                            delete: { delete(record) },
                            preferContextMenuOnly: runsOnMac
                        )
                }
            }
            .id("history-single")
        }
    }

    @ViewBuilder
    private var historyDetail: some View {
        if isEditing {
            ContentUnavailableView(
                "Selecting codes",
                systemImage: "checkmark.circle",
                description: Text(runsOnMac
                                  ? "Click the circles in the list, then copy, share or delete."
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
                Image(systemName: isBulkSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isBulkSelected ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(isBulkSelected ? "Selected" : "Not selected")
            }

            Image(systemName: content.icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.value)
                    .lineLimit(1)

                Text(record.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }

    private func toggleBulkSelection(_ id: PersistentIdentifier) {
        if bulkSelection.contains(id) {
            bulkSelection.remove(id)
        } else {
            bulkSelection.insert(id)
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
            // Avoid animating the List selection-type swap — it can trap in AppKit layout.
            if isEditing {
                isEditing = false
                bulkSelection.removeAll()
            } else {
                isEditing = true
                bulkSelection.removeAll()
                selectedCodeID = nil
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
    }

    private var deleteSelectedButton: some View {
        #if os(macOS)
        Button("Delete", role: .destructive) {
            confirmDelete = true
        }
        .disabled(bulkSelection.isEmpty)
        #else
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Image(systemName: "trash")
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(.red)
        .disabled(bulkSelection.isEmpty)
        .accessibilityLabel("Delete")
        #endif
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

            ShareLink(
                item: HistoryTextFileExport(records: selectedRecords),
                preview: SharePreview("Quby codes.txt")
            ) {
                Label("Export as text file", systemImage: "doc.text")
            }

            Menu {
                ShareLink(
                    item: HistoryCSVPackageExport(records: selectedRecords),
                    preview: SharePreview("Quby codes.zip")
                ) {
                    Label("With images", systemImage: "photo.on.rectangle.angled")
                }
                ShareLink(
                    item: HistoryCSVExport(records: selectedRecords),
                    preview: SharePreview("Quby codes.csv")
                ) {
                    Label("Without images", systemImage: "text.menu")
                }
            } label: {
                Label("Export as CSV", systemImage: "text.rectangle")
            }

            Menu {
                ShareLink(
                    item: HistoryExcelExport(records: selectedRecords, withImages: true),
                    preview: SharePreview("Quby codes with images.xlsx")
                ) {
                    Label("With embedded images", systemImage: "photo.on.rectangle.angled")
                }
                ShareLink(
                    item: HistoryExcelExport(records: selectedRecords, withImages: false),
                    preview: SharePreview("Quby codes.xlsx")
                ) {
                    Label("Without images", systemImage: "text.menu")
                }
            } label: {
                Label("Export as Excel", systemImage: "tablecells")
            }

            ShareLink(
                item: HistoryJSONExport(records: selectedRecords),
                preview: SharePreview("Quby codes.json")
            ) {
                Label("Export as JSON", systemImage: "curlybraces")
            }

            Menu {
                ShareLink(
                    item: HistoryPDFExport(records: selectedRecords, withImages: true),
                    preview: SharePreview("Quby codes with images.pdf")
                ) {
                    Label("With images", systemImage: "photo.on.rectangle.angled")
                }
                ShareLink(
                    item: HistoryPDFExport(records: selectedRecords, withImages: false),
                    preview: SharePreview("Quby codes.pdf")
                ) {
                    Label("Without images", systemImage: "text.menu")
                }
            } label: {
                Label("Export as PDF", systemImage: "doc.richtext")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(bulkSelection.isEmpty)
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

            if hasNonDefaultFilters {
                Divider()

                Button("Reset filters", role: .destructive) {
                    withAnimation(.smooth(duration: 0.35)) {
                        resetFilters()
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: hasNonDefaultFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
            .foregroundStyle(hasNonDefaultFilters ? Color.accentColor : Color.primary)
        }
        .help("Filter and sort history")
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
        bulkSelection.removeAll()
        isEditing = false
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
