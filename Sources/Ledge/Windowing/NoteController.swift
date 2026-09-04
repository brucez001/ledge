import AppKit
import Combine

/// Owns the note store and every open note window.
///
/// Kept as its own small type rather than growing `PanelController` (the
/// project convention): the panel and the status item only forward the
/// entry points they need -- `⌘N`, the Home tiles, and the menu-bar Notes
/// list.
@MainActor
final class NoteController: ObservableObject {
    let store = NoteStore()

    /// Note ids with a window currently open, published so the Home grid
    /// can mark visiting tiles.
    @Published private(set) var openNoteIDs = Set<UUID>()

    private var windowControllers: [NoteWindowController] = []

    /// ⌘N / "New Note": create a fresh note file and open its window.
    func openNewNote() {
        open(store.createNewNote())
    }

    /// Opens a saved note, focusing its existing window when one is already
    /// open rather than stacking a duplicate editor.
    func open(_ note: Note) {
        if let existing = windowFor(note) {
            existing.show()
            return
        }
        let controller = NoteWindowController(store: store, note: note) { [weak self] closed in
            guard let self else { return }
            self.windowControllers.removeAll { $0 === closed }
            self.openNoteIDs.remove(closed.note.id)
        }
        windowControllers.append(controller)
        openNoteIDs.insert(note.id)
        controller.show()
    }

    func windowFor(_ note: Note) -> NoteWindowController? {
        windowControllers.first { $0.note.id == note.id }
    }

    /// ⌘W while a note window is key: save and close it.
    func close(_ window: NoteWindow) {
        guard let controller = windowControllers.first(where: { $0.matches(window) }) else { return }
        controller.requestClose()
    }

    /// Saves every still-open note window so a quit mid-keystroke can't lose
    /// the last few characters.
    func saveAllOpen() {
        for controller in windowControllers {
            controller.saveNow()
        }
    }
}
