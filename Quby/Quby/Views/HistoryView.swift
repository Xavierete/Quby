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
}

struct HistoryView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CodeRecord.createdAt, order: .reverse) private var records: [CodeRecord]
    @State private var favoritesFilter: HistoryFavoritesFilter = .all
    @State private var typeFilter: HistoryTypeFilter = .all
    @State private var sortOrder: HistorySortOrder = .newest
    @State private var searchText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selectedCodeID: PersistentIdentifier?
    @State private var confirmDelete = false

    private var isEditing: Bool { editMode.isEditing }

    private var hasNonDefaultFilters: Bool {
        typeFilter != .all || favoritesFilter == .favoritesOnly || sortOrder != .newest
    }

    private var shown: [CodeRecord] {
        let sorted = sortOrder == .newest ? records : records.reversed()
        return sorted.filter { record in
            if favoritesFilter == .favoritesOnly && !record.isFavorite { return false }

            if !searchText.isEmpty,
               !record.value.localizedCaseInsensitiveContains(searchText) {
                return false
            }

            return true
        }
    }

    private var selectedRecord: CodeRecord? {
        guard let selectedCodeID else { return nil }
        return records.first { $0.persistentModelID == selectedCodeID }
    }

    var body: some View {
        NavigationSplitView {
            historySidebar
        } detail: {
            NavigationStack {
                historyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .alert("Delete this code?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .onChange(of: shown.map(\.persistentModelID)) { _, visibleIDs in
            if let selectedCodeID, !visibleIDs.contains(selectedCodeID) {
                self.selectedCodeID = nil
            }
        }
    }

    private var historySidebar: some View {
        List(selection: $selectedCodeID) {
            ForEach(shown) { record in
                NavigationLink(value: record.persistentModelID) {
                    row(for: record)
                }
                .historyRowActions(
                    favorite: { record.isFavorite.toggle() },
                    isFavorite: record.isFavorite,
                    delete: { delete(record) }
                )
            }
        }
        .navigationTitle(isEditing ? "Select codes" : "History")
        .toolbarTitleDisplayMode(isEditing ? .inline : .inlineLarge)
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search codes")
        .environment(\.editMode, $editMode)
        .toolbar { toolbarContent }
        .overlay {
            if shown.isEmpty {
                emptyState
            }
        }
    }

    @ViewBuilder
    private var historyDetail: some View {
        if isEditing {
            ContentUnavailableView(
                "Selecting codes",
                systemImage: "checkmark.circle",
                description: Text("Choose codes in the list, then copy, share or delete.")
            )
            .navigationTitle("History")
            .toolbarTitleDisplayMode(.inline)
        } else if let selectedRecord {
            CodeDetailView(record: selectedRecord)
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
                description: Text("Swipe a row to the right to star it.")
            )
        } else {
            ContentUnavailableView(
                "Nothing yet",
                systemImage: "clock",
                description: Text("Codes you scan or create show up here.")
            )
        }
    }

    private func row(for record: CodeRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.value)
                    .lineLimit(1)

                Text(record.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if record.isFavorite {
                Image(systemName: "star.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.yellow.gradient)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            selectButton
        }

        if isEditing {
            ToolbarItem(placement: .topBarTrailing) { deleteSelectedButton }
            ToolbarItem(placement: .topBarTrailing) { copySelectedButton }
            ToolbarItem(placement: .topBarTrailing) { shareSelectedButton }
        } else {
            ToolbarItem { filterMenu }
        }
    }

    private var selectButton: some View {
        Button(isEditing ? "Done" : "Select") {
            withAnimation {
                if isEditing {
                    editMode = .inactive
                    selectedCodeID = nil
                } else {
                    editMode = .active
                    selectedCodeID = nil
                }
            }
        }
        .disabled(shown.isEmpty && !isEditing)
    }

    private var deleteSelectedButton: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(true)
    }

    private var copySelectedButton: some View {
        Button {
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(true)
    }

    private var shareSelectedButton: some View {
        Menu {
            Button {
            } label: {
                Label("Share as text", systemImage: "text.alignleft")
            }
            Button {
            } label: {
                Label("Export as text file", systemImage: "doc.text")
            }
            Button {
            } label: {
                Label("Export as CSV", systemImage: "tablecells")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(true)
    }

    private var filterMenu: some View {
        Menu {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                macFilterSections
            } else {
                HistoryTypeFilterSubmenu(selection: $typeFilter)
                HistorySortSubmenu(selection: $sortOrder)
                HistoryFavoritesSubmenu(selection: $favoritesFilter)
            }

            if hasNonDefaultFilters {
                Divider()

                Button("Reset filters", role: .destructive) {
                    typeFilter = .all
                    favoritesFilter = .all
                    sortOrder = .newest
                }
            }
        } label: {
            Label("Filter", systemImage: hasNonDefaultFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
            .foregroundStyle(hasNonDefaultFilters ? Color.accentColor : Color.primary)
        }
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

    private func delete(_ record: CodeRecord) {
        let id = record.persistentModelID
        withAnimation {
            modelContext.delete(record)
            if selectedCodeID == id { selectedCodeID = nil }
        }
    }
}

private extension View {
    func historyRowActions(
        favorite: @escaping () -> Void,
        isFavorite: Bool,
        delete: @escaping () -> Void
    ) -> some View {
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
