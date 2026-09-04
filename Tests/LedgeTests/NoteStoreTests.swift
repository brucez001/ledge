import XCTest
@testable import Ledge

@MainActor
final class NoteStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> NoteStore {
        NoteStore(directory: directory)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("md")
    }

    func testCreateWritesAFileAndRegistersTheNote() {
        let store = makeStore()
        let note = store.createNewNote()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL(for: note.id).path))
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.id, note.id)
    }

    func testSaveRoundTripsThroughAFreshStore() {
        let store = makeStore()
        var note = store.createNewNote()
        note.body = "Shopping list\n\n- milk\n- eggs"
        store.save(note)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.body, "Shopping list\n\n- milk\n- eggs")
    }

    func testDeleteRemovesFileAndEntry() {
        let store = makeStore()
        let note = store.createNewNote()

        store.delete(note)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL(for: note.id).path))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNil(makeStore().note(withID: note.id))
    }

    func testCorruptFileIsSkippedWithoutCrashing() throws {
        let id = UUID()
        try Data([0xFF, 0xFE, 0x00]).write(to: fileURL(for: id))

        let store = makeStore()

        XCTAssertTrue(store.notes.isEmpty, "An undecodable note file must never take the list down")
    }

    func testNonNoteFilesInTheDirectoryAreIgnored() throws {
        try Data("not a note".utf8).write(to: directory.appendingPathComponent("scratch.txt"))

        let store = makeStore()

        XCTAssertTrue(store.notes.isEmpty)
    }

    func testTitleFromFirstNonEmptyLine() {
        let note = Note(id: UUID(), body: "\n\n# Shopping list\n- milk", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(note.title, "Shopping list")
    }

    func testTitleFallsBackWhenBodyIsEmpty() {
        XCTAssertEqual(Note.title(from: ""), "Note")
        XCTAssertEqual(Note.title(from: "\n  \n"), "Note")
    }

    func testTitleIsTruncated() {
        let long = String(repeating: "x", count: 80)
        let title = Note.title(from: long)
        XCTAssertEqual(title.count, Note.maxTitleLength + 1, "Truncated title plus the ellipsis")
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testPreviewDropsTheTitleLine() {
        let note = Note(id: UUID(), body: "Shopping list\n- milk\n- eggs", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(note.preview, "- milk")
    }

    func testOrdersByUpdatedAtDescending() {
        let store = makeStore()
        var first = store.createNewNote()
        first.body = "first"
        store.save(first)

        Thread.sleep(forTimeInterval: 0.05)

        var second = store.createNewNote()
        second.body = "second"
        store.save(second)

        XCTAssertEqual(store.notes.map(\.body), ["second", "first"])
        XCTAssertEqual(store.notes.first?.updatedAt, store.notes[0].updatedAt)
    }
}
