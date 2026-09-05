import Combine
import Foundation

/// One open note tab in the panel rail: a live editor over a single
/// persisted `Note`.
///
/// The tab is ephemeral, exactly like an open session -- it is never
/// restored across launches and carries no web content. Its body is
/// autosaved to disk on a short debounce and again when the tab closes, so
/// closing never loses text. Deleting a note never touches a session,
/// favourite, or the panel itself.
@MainActor
final class NoteTab: ObservableObject, Identifiable {
    private let store: NoteStore

    /// Stored out-of-line (rather than derived from `note`) so the
    /// `Identifiable` conformance stays nonisolated under Swift 6.
    nonisolated let id: UUID

    /// The note this tab is editing; `note.body` only advances on save,
    /// while `body` is the live per-keystroke buffer.
    @Published private(set) var note: Note
    /// The live draft. SwiftUI binds `TextEditor` straight to this, so a
    /// keystroke re-renders the editor without churning the store.
    @Published var body: String
    /// Bumped whenever the editor should reclaim keyboard focus -- the tab
    /// is opened or re-selected. The editor must win focus over the panel's
    /// toolbar the moment a note opens, or the user's first keystroke would
    /// go to a control instead of the text.
    @Published private(set) var focusToken = 0
    /// Whether the tab is showing the rendered Markdown preview rather than
    /// the raw text. Per tab, and deliberately not persisted: like the tab
    /// itself, the mode is part of this session's workspace, and a note
    /// always reopens ready to edit.
    @Published var isPreviewing = false

    private var autosaveTask: Task<Void, Never>?
    /// Set before deleting so the close path cannot re-save the file the
    /// user just asked to remove.
    private var isRemoving = false

    init(store: NoteStore, note: Note) {
        self.store = store
        self.id = note.id
        self.note = note
        self.body = note.body
    }

    /// Saves immediately, killing any pending autosave. Used on tab close
    /// and app termination so the last few keystrokes are never lost.
    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard !isRemoving, body != note.body else { return }
        var updated = note
        updated.body = body
        note = store.save(updated)
    }

    /// Delete is the only destructive note action; callers must already
    /// have confirmed it with the user. The file is removed here and the
    /// tab is retired by the controller.
    func deleteNote() {
        guard !isRemoving else { return }
        isRemoving = true
        store.delete(note)
    }

    /// Called as the editor buffer changes; (re)arms the debounced
    /// autosave. The note's name is deliberately untouched -- editing the
    /// text never renames the note.
    func bodyDidChange() {
        autosaveTask?.cancel()
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
        autosaveTask = task
    }

    func bumpFocus() {
        focusToken += 1
    }

    /// The title as the rail, header, and dialogs show it: trimmed and
    /// truncated, never blank.
    var displayTitle: String {
        note.displayTitle
    }

    /// Renames the note. The name is its own stored value, so this leaves
    /// the Markdown completely alone; a blank name is a slip of the
    /// keyboard rather than a request to erase the note's name, so it is
    /// ignored.
    func rename(to newTitle: String) {
        let cleaned = Note.sanitisedTitle(newTitle)
        guard !cleaned.isEmpty, cleaned != note.title else { return }
        var updated = note
        updated.title = cleaned
        // Fold in whatever is on screen, so renaming can never rewind the
        // draft to the last autosave.
        updated.body = body
        note = store.save(updated)
    }

    /// ⇧⌘P and the header's book/pencil button. Swapping modes must never
    /// touch the text, so the pending autosave is left exactly as it is.
    func togglePreview() {
        isPreviewing.toggle()
    }
}
