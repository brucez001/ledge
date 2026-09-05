import Foundation
import Combine

/// Owns the locally persisted note files.
///
/// One file per note (named `<UUID>.md`) under `Notes/`. The store is the
/// single owner of note ordering and persistence; open note tabs are just
/// editors over a note's body. Files are the source of truth, so notes
/// survive launches (and even survive this app being deleted) and nothing
/// needs a database or a migration: a note's title rides above its text in
/// a front-matter block (see `NoteFile`), and an older file without one is
/// simply named from its first line when it loads.
@MainActor
final class NoteStore: ObservableObject {
    /// Most recently edited first.
    @Published private(set) var notes: [Note] = []

    /// The default location: `~/Library/Application Support/Ledge/Notes/`.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Ledge/Notes", isDirectory: true)
    }

    private let directory: URL
    private let fileManager: FileManager

    /// `directory` is injectable so tests never touch real user files.
    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Persistence

    /// Creates an empty note on disk and returns it.
    @discardableResult
    func createNewNote() -> Note {
        // A new note is named rather than left blank so the rail, the
        // menu, and the Home grid have something to say before a word is
        // typed -- and numbered so two unnamed notes are still telling
        // apart at a glance.
        let note = Note(
            id: UUID(),
            title: unusedUntitledName(),
            body: "",
            createdAt: Date(),
            updatedAt: Date()
        )
        write(note)
        insert(note)
        return note
    }

    /// Writes the note's current body, bumping `updatedAt` so recently
    /// edited notes rise to the top of the Home list.
    @discardableResult
    func save(_ note: Note) -> Note {
        var updated = note
        updated.updatedAt = Date()
        write(updated)
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return updated }
        notes[index] = updated
        resort()
        return updated
    }

    /// Permanently removes a note's file. Destructive callers must have
    /// already confirmed the action with the user.
    func delete(_ note: Note) {
        try? fileManager.removeItem(at: fileURL(for: note.id))
        notes.removeAll { $0.id == note.id }
    }

    func note(withID id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    // MARK: - Loading

    private func load() {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        notes = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(loadNote(from:))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Reads one note file. A missing UUID in the filename or undecodable
    /// contents is skipped without crashing -- a torn file must never take
    /// the whole list down with it.
    private func loadNote(from url: URL) -> Note? {
        guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
              let data = fileManager.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parsed = NoteFile.parse(text)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let createdAt = attributes?[.creationDate] as? Date ?? Date()
        let updatedAt = attributes?[.modificationDate] as? Date ?? Date()
        // A file written before titles were stored keeps the name its
        // owner already knows it by: its first line. The body is left
        // exactly as written -- naming a note must never edit it.
        let title = parsed.title.isEmpty ? Note.inferredTitle(from: parsed.body) : parsed.title
        return Note(
            id: id,
            title: title,
            body: parsed.body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            extraFrontMatter: parsed.extraFrontMatter
        )
    }

    private func write(_ note: Note) {
        let text = NoteFile.serialise(
            title: note.title,
            extraFrontMatter: note.extraFrontMatter,
            body: note.body
        )
        guard let data = text.data(using: .utf8) else { return }
        do {
            // Atomic: write a temp file and swap it into place, so a crash
            // mid-save can never truncate a note to a half-written file.
            try data.write(to: fileURL(for: note.id), options: .atomic)
            // The atomic replace renames a fresh inode in, which would
            // otherwise reset the creation date to *now*; put the real one
            // back and stamp the modification time the note records.
            var attributes: [FileAttributeKey: Any] = [:]
            if note.createdAt.timeIntervalSince1970 > 0 {
                attributes[.creationDate] = note.createdAt
            }
            attributes[.modificationDate] = note.updatedAt
            try? fileManager.setAttributes(attributes, ofItemAtPath: fileURL(for: note.id).path)
        } catch {
            // Persistence is best-effort per keystroke; a failed autosave
            // must never crash the editor. The in-memory note stays current.
            // The error is deliberately swallowed: a note that cannot be
            // written (read-only disk, sandbox hiccup) is still editable
            // in memory until the next successful save.
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("md")
    }

    /// "New Note", then "New Note 2": a name a user can tell apart, rather
    /// than a grid of identical tiles.
    private func unusedUntitledName() -> String {
        let taken = Set(notes.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard taken.contains(Note.untitledTitle) else { return Note.untitledTitle }
        var index = 2
        while taken.contains("\(Note.untitledTitle) \(index)") { index += 1 }
        return "\(Note.untitledTitle) \(index)"
    }

    private func insert(_ note: Note) {
        notes.append(note)
        resort()
    }

    private func resort() {
        notes.sort { $0.updatedAt > $1.updatedAt }
    }
}
