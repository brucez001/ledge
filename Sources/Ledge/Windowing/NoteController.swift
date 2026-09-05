import Combine
import Foundation

/// Owns the note store and every open note tab.
///
/// Kept as its own small type rather than growing `PanelController` (the
/// project convention): the panel and the status item only forward the
/// entry points they need -- `⌘N`, the Home tiles, and the menu-bar Notes
/// list.
///
/// Note tabs are exactly like sessions: they live in memory, appear in the
/// rail in open order, and are never restored across launches. The notes
/// themselves are plain files owned by `NoteStore`.
@MainActor
final class NoteController: ObservableObject {
    let store: NoteStore

    /// Open note tabs in rail order.
    @Published private(set) var tabs: [NoteTab] = []

    /// `store` is injectable so tests never touch real user files.
    init(store: NoteStore = NoteStore()) {
        self.store = store
    }

    /// Note ids with a tab currently open, so the Home grid can mark
    /// visiting tiles.
    var openNoteIDs: Set<UUID> {
        Set(tabs.map(\.note.id))
    }

    /// ⌘N / "New Note": create a fresh note file and open its tab.
    @discardableResult
    func openNewNote() -> NoteTab {
        open(store.createNewNote())
    }

    /// Opens a saved note, reusing an already-open tab rather than stacking
    /// a duplicate editor.
    @discardableResult
    func open(_ note: Note) -> NoteTab {
        if let existing = tab(for: note.id) {
            return existing
        }
        let tab = NoteTab(store: store, note: note)
        tabs.append(tab)
        return tab
    }

    func tab(for id: UUID) -> NoteTab? {
        tabs.first { $0.note.id == id }
    }

    /// ⌘W on a note tab: save and close it. The note itself stays on disk.
    func close(_ id: UUID) {
        guard let tab = tab(for: id) else { return }
        tab.saveNow()
        remove(id)
    }

    /// Removes a note's file and retires its tab. Destructive callers must
    /// have already confirmed the action with the user.
    func delete(_ id: UUID) {
        guard let tab = tab(for: id) else { return }
        tab.deleteNote()
        remove(id)
    }

    /// Reorders open tabs after validating a true permutation.
    func setNoteOrder(_ ids: [UUID]) {
        let current = tabs.map(\.id)
        let reordered = ids.compactMap { tab(for: $0) }
        guard Set(reordered.map(\.id)) == Set(current), reordered.count == current.count else { return }
        guard reordered.map(\.id) != current else { return }
        tabs = reordered
    }

    /// Flushes every still-open tab so a quit mid-keystroke can't lose the
    /// last few characters.
    func saveAllOpen() {
        for tab in tabs {
            tab.saveNow()
        }
    }

    private func remove(_ id: UUID) {
        tabs.removeAll { $0.note.id == id }
    }
}
