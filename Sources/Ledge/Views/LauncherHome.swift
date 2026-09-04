import SwiftUI

struct LauncherHome: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var favourites: FavouritesStore
    @ObservedObject var preferences: Preferences
    @ObservedObject private var noteController: NoteController
    @ObservedObject private var noteStore: NoteStore

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var isShowingFavouritesManager = false

    init(controller: PanelController, favourites: FavouritesStore, preferences: Preferences) {
        self.controller = controller
        self.favourites = favourites
        self.preferences = preferences
        let notes = controller.noteController
        self.noteController = notes
        self.noteStore = notes.store
    }

    private let columns = [
        GridItem(.adaptive(minimum: Theme.Metrics.tileSize, maximum: Theme.Metrics.tileSize), spacing: 20, alignment: .leading)
    ]

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Favourites matching the typed text by name or host, case-insensitive.
    private var matchingFavourites: [Favourite] {
        guard !trimmedQuery.isEmpty else { return [] }
        return favourites.items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery) || $0.host.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    /// The "Search for …" / "Go to …" row derived straight from the same
    /// resolver the toolbar's address field uses, so the suggestion and
    /// what actually happens on submit never disagree.
    private var addressSuggestion: (url: URL, isSearch: Bool)? {
        guard !trimmedQuery.isEmpty,
              let resolved = AddressResolver.resolve(trimmedQuery, using: preferences.searchEngine) else { return nil }
        let isSearch = resolved == preferences.searchEngine.searchURL(for: trimmedQuery)
        return (resolved, isSearch)
    }

    private var isShowingSuggestions: Bool {
        !trimmedQuery.isEmpty && (!matchingFavourites.isEmpty || addressSuggestion != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                omnibox
                    .padding(.top, 56)

                if isShowingSuggestions {
                    suggestionsList
                        .padding(.top, 10)
                }

                if favourites.items.isEmpty {
                    emptyState
                        .padding(.top, 64)
                } else {
                    HStack {
                        Text("Favourites")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text("\(favourites.items.count)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(.top, 44)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(favourites.items) { item in
                            FavouriteTile(
                                controller: controller,
                                item: item,
                                isActive: controller.destination == .favourite(item.id)
                            )
                        }

                        AddTile(
                            action: controller.openAddFavourite,
                            onDropFavourite: { favourites.moveToEnd(id: $0) }
                        )
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }

                notesSection
            }
            .padding(.horizontal, 36)
        }
        .scrollIndicators(.hidden)
        .contentShape(Rectangle())
        .onTapGesture {
            searchFocused = false
        }
        .onChange(of: controller.homeFocusToken) { _, _ in
            requestSearchFocus()
        }
        .task {
            requestSearchFocus()
        }
        .sheet(isPresented: $isShowingFavouritesManager) {
            FavouritesManagerSheet(controller: controller)
        }
    }

    /// A hidden home view can retain `true` in its `FocusState` after the
    /// browser takes over. Setting the same value again when a new blank tab
    /// is selected therefore does not always send a fresh first-responder
    /// request. Bounce the state, then reclaim focus on the next run-loop turn
    /// after the home view is visible again.
    private func requestSearchFocus() {
        guard controller.showsStartPage else { return }
        searchFocused = false
        DispatchQueue.main.async {
            guard controller.showsStartPage else { return }
            searchFocused = true
        }
    }

    // MARK: - Omnibox

    private var omnibox: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            TextField(
                "Search \(preferences.searchEngine.title) or enter an address",
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Theme.ink)
            .submitLabel(.go)
            .focused($searchFocused)
            .onSubmit(submit)

            Button {
                isShowingFavouritesManager = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Manage favourites")
            .accessibilityLabel("Manage favourites")
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Theme.card, in: Capsule())
        .shadow(color: Theme.shadow(isDark: false).opacity(0.4), radius: 15, y: 9)
    }

    /// Return opens the top favourite match if the typed text matches one,
    /// otherwise performs the search/navigation -- shared with tapping a
    /// suggestion row so the two paths can never disagree.
    private func submit() {
        guard !trimmedQuery.isEmpty else { return }
        if let topMatch = matchingFavourites.first {
            controller.openFavourite(topMatch)
        } else {
            controller.open(address: trimmedQuery)
        }
        searchText = ""
    }

    private func openSuggestion(_ favourite: Favourite) {
        controller.openFavourite(favourite)
        searchText = ""
    }

    private func openAddressSuggestion() {
        controller.open(address: trimmedQuery)
        searchText = ""
    }

    // MARK: - Suggestions

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matchingFavourites.prefix(5)) { favourite in
                Button {
                    openSuggestion(favourite)
                } label: {
                    HStack(spacing: 10) {
                        FaviconView(host: favourite.host, size: 20)
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(favourite.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text(favourite.host)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if favourite.id != matchingFavourites.prefix(5).last?.id || addressSuggestion != nil {
                    Divider().padding(.leading, 44)
                }
            }

            if let suggestion = addressSuggestion {
                Button(action: openAddressSuggestion) {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.isSearch ? "magnifyingglass" : "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 20, height: 20)
                        Text(suggestion.isSearch ? "Search for \u{201C}\(trimmedQuery)\u{201D}" : "Go to \(trimmedQuery)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }

    // MARK: - Empty state

    /// The discoverable entry point for notes. With no notes yet this is a
    /// slim "New note" button; once notes exist it becomes a titled grid of
    /// tiles plus the same add affordance the favourites grid has.
    @ViewBuilder
    private var notesSection: some View {
        if noteStore.notes.isEmpty {
            Button(action: controller.openNewNote) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("New note")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(
                    Theme.card,
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New note (⌘N)")
            .accessibilityLabel("Create a new note")
            .padding(.top, 32)
        } else {
            HStack {
                Text("Notes")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("\(noteStore.notes.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.top, 44)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(noteStore.notes) { note in
                    NoteTile(
                        note: note,
                        isOpen: noteController.openNoteIDs.contains(note.id),
                        open: { controller.openNote(note) }
                    )
                }
                NewNoteTile(action: controller.openNewNote)
            }
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.inkTertiary)

            Text("No favourites yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("Add sites you visit often for one-click access from this screen.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Button("Add your first site") {
                controller.openAddFavourite()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FavouritesManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: PanelController
    @ObservedObject private var favourites: FavouritesStore

    init(controller: PanelController) {
        self.controller = controller
        self.favourites = controller.favourites
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Favourites")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                Button("Add") {
                    dismiss()
                    controller.openAddFavourite()
                }
            }

            List {
                ForEach(favourites.items) { favourite in
                    FavouriteManagerRow(controller: controller, favourite: favourite) {
                        dismiss()
                    }
                }
                .onMove(perform: favourites.move)
            }
            .frame(height: 300)

            HStack {
                Text("Drag rows to reorder. Sites can also be dragged directly on the home grid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

/// One editable Home shortcut: rename, open, or remove it.
private struct FavouriteManagerRow: View {
    @ObservedObject var controller: PanelController
    let favourite: Favourite
    let onOpen: () -> Void

    /// Deleting from the manager list is as destructive as deleting from a
    /// tile, and the trash button sits next to "Open", so it asks exactly the
    /// same question the tile and rail menus do.
    @State private var isConfirmingRemoval = false

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(host: favourite.host, size: 22)
                .frame(width: 22, height: 22)

            RenamableNameField(initialName: favourite.name) { newName in
                controller.favourites.rename(favourite, to: newName)
            }

            Spacer()

            Button("Open") {
                controller.openFavourite(favourite)
                onOpen()
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                isConfirmingRemoval = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove favourite")
            .accessibilityLabel("Remove \(favourite.name)")
            .confirmFavouriteRemoval(favourite, isPresented: $isConfirmingRemoval) {
                controller.removeFavourite(favourite)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Self-contained inline rename field. Owns its own draft text so typing
/// doesn't force a `FavouritesStore` write (and a full list re-render) on
/// every keystroke; the rename is only committed on submit or blur.
private struct RenamableNameField: View {
    let initialName: String
    let commit: (String) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(initialName: String, commit: @escaping (String) -> Void) {
        self.initialName = initialName
        self.commit = commit
        _text = State(initialValue: initialName)
    }

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit { commit(text) }
            .onChange(of: isFocused) { _, focused in
                guard !focused else { return }
                commit(text)
            }
    }
}
