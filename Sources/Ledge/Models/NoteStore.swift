import Foundation
import Combine

/// Owns the locally persisted note files.
///
/// One file per note (named `<UUID>.md`) under `Notes/`. The store is the
/// single owner of note ordering and persistence; note windows are just
/// editors over a note's body. Files are the source of truth, so notes
/// survive launches (and even survive this app being deleted) and nothing
/// needs a schema or a migration.
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
        let note = Note(id: UUID(), body: "", createdAt: Date(), updatedAt: Date())
        write(note)
        insert(note)
        return note
    }

    /// Writes the note's current body, bumping `updatedAt` so recently
    /// edited notes rise to the top of the Home list.
    func save(_ note: Note) {
        var updated = note
        updated.updatedAt = Date()
        write(updated)
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = updated
        resort()
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
              let body = String(data: data, encoding: .utf8) else {
            return nil
        }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let createdAt = attributes?[.creationDate] as? Date ?? Date()
        let updatedAt = attributes?[.modificationDate] as? Date ?? Date()
        return Note(id: id, body: body, createdAt: createdAt, updatedAt: updatedAt)
    }

    private func write(_ note: Note) {
        guard let data = note.body.data(using: .utf8) else { return }
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

    private func insert(_ note: Note) {
        notes.append(note)
        resort()
    }

    private func resort() {
        notes.sort { $0.updatedAt > $1.updatedAt }
    }
}
