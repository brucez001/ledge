import AppKit
import SwiftUI

/// One open note window: an editor over a single persisted `Note`.
///
/// The window is ephemeral, exactly like an open session. Its body is
/// autosaved to disk on a short debounce and again on close, so closing
/// never loses text. Closing or deleting a note never touches a session,
/// favourite, or the panel itself.
@MainActor
final class NoteWindowController: NSObject, ObservableObject, NSWindowDelegate {
    let store: NoteStore

    /// The note this window is editing; `note.body` only advances on save,
    /// while `body` is the live per-keystroke buffer.
    private(set) var note: Note
    /// The live draft. SwiftUI binds `TextEditor` straight to this, so a
    /// keystroke re-renders the editor without churning the store.
    @Published var body: String
    /// The window title, re-derived from `body` as the first line changes.
    @Published private(set) var title: String
    /// Bumped whenever the editor should reclaim keyboard focus (the window
    /// is created or becomes key). The editor must win focus over the
    /// toolbar's buttons the moment a note opens, or the user's first
    /// keystroke would go to a control instead of the text.
    @Published private(set) var focusToken = 0

    private let onClose: (NoteWindowController) -> Void
    private var window: NoteWindow?
    private var autosaveTask: Task<Void, Never>?
    /// Set before deleting so the delegate / close path cannot re-save the
    /// file the user just asked to remove.
    private var isRemoving = false

    init(
        store: NoteStore,
        note: Note,
        onClose: @escaping (NoteWindowController) -> Void
    ) {
        self.store = store
        self.note = note
        self.body = note.body
        self.title = note.title
        self.onClose = onClose
        super.init()
    }

    func matches(_ candidate: NoteWindow) -> Bool {
        window === candidate
    }

    // MARK: - Showing and closing

    func show() {
        let isNewWindow = window == nil
        if isNewWindow {
            window = makeWindow()
        }
        // A note is summoned to be typed into, so it takes key focus even
        // though Ledge runs as an accessory app with no Dock entry.
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // A freshly created window needs a beat before its SwiftUI content
        // is wired up; focus is reclaimed again from `windowDidBecomeKey`
        // for the window that already exists.
        if isNewWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.bumpFocus()
            }
        } else {
            bumpFocus()
        }
    }

    /// ⌘W (and the note window's own close button via `windowWillClose`).
    func requestClose() {
        guard !isRemoving else { return }
        saveNow()
        closeWindow()
    }

    /// Saves immediately, killing any pending autosave. Used on close and on
    /// app termination so the last few keystrokes are never lost.
    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard body != note.body else { return }
        var updated = note
        updated.body = body
        updated.updatedAt = Date()
        note = updated
        store.save(updated)
    }

    /// Delete is the only destructive note action; callers must already
    /// have confirmed it with the user.
    func deleteNote() {
        guard !isRemoving else { return }
        isRemoving = true
        store.delete(note)
        closeWindow()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isRemoving else { return }
        saveNow()
        onClose(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        bumpFocus()
    }

    func bumpFocus() {
        focusToken += 1
    }

    private func closeWindow() {
        if let window {
            // Bypass the delegate path: `closeWindow` already does whatever
            // the close should do (save or delete), so `windowWillClose`
            // must not fire a second time.
            window.delegate = nil
            window.close()
        }
        onClose(self)
    }

    private func makeWindow() -> NoteWindow {
        let size = NSSize(width: 420, height: 480)
        let window = NoteWindow(contentRect: NSRect(origin: .zero, size: size))
        window.contentView = NSHostingView(rootView: NoteEditorView(controller: self))
        window.delegate = self
        window.title = title
        // First appearance: centre the note on the screen under the pointer
        // (falling back to the main screen), so a fresh note never lands on
        // top of the docked panel or in a corner of the desktop.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: false)
        }
        return window
    }

    // MARK: - Editing

    /// Called as the editor buffer changes; keeps the window title in step
    /// with the first line and (re)arms the debounced autosave.
    func bodyDidChange() {
        let updatedTitle = Note.title(from: body)
        if updatedTitle != title {
            title = updatedTitle
            window?.title = updatedTitle
        }
        autosaveTask?.cancel()
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
        autosaveTask = task
    }
}
