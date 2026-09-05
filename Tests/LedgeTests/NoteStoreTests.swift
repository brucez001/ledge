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

    func testTitleIsIndependentOfTheBody() {
        let note = Note(
            id: UUID(),
            title: "Groceries",
            body: "# Weekend plans\n- milk",
            createdAt: Date(),
            updatedAt: Date()
        )
        // The heading is part of the note, not its name.
        XCTAssertEqual(note.title, "Groceries")
        XCTAssertEqual(note.displayTitle, "Groceries")
    }

    func testDisplayTitleFallsBackWhenTheNoteIsUnnamed() {
        XCTAssertEqual(Note.displayTitle(for: ""), Note.untitledTitle)
        XCTAssertEqual(Note.displayTitle(for: "   "), Note.untitledTitle)
    }

    func testDisplayTitleIsTruncated() {
        let long = String(repeating: "x", count: 80)
        let title = Note.displayTitle(for: long)
        XCTAssertEqual(title.count, Note.maxTitleLength + 1, "Truncated title plus the ellipsis")
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testSanitisedTitleCollapsesAPastedParagraph() {
        XCTAssertEqual(Note.sanitisedTitle("  Two\nlines  "), "Two lines")
        XCTAssertEqual(Note.sanitisedTitle("   "), "")
    }

    func testNewNotesAreNamedAndNumbered() {
        let store = makeStore()

        let first = store.createNewNote()
        let second = store.createNewNote()

        XCTAssertEqual(first.title, Note.untitledTitle)
        XCTAssertEqual(second.title, "\(Note.untitledTitle) 2")
    }

    func testTitleRoundTripsWithoutTouchingTheBody() throws {
        let store = makeStore()
        var note = store.createNewNote()
        note.title = "Groceries"
        note.body = "# Weekend\n- milk"
        store.save(note)

        let text = try String(contentsOf: fileURL(for: note.id), encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("---\ntitle: Groceries\n---\n"))
        XCTAssertTrue(text.hasSuffix("# Weekend\n- milk"), "Renaming must never rewrite the Markdown")

        let reloaded = makeStore().note(withID: note.id)
        XCTAssertEqual(reloaded?.title, "Groceries")
        XCTAssertEqual(reloaded?.body, "# Weekend\n- milk")
    }

    func testAnUnnamedNoteIsWrittenWithoutFrontMatter() throws {
        let store = makeStore()
        var note = store.createNewNote()
        note.title = ""
        note.body = "just text"
        store.save(note)

        let text = try String(contentsOf: fileURL(for: note.id), encoding: .utf8)
        XCTAssertEqual(text, "just text")
    }

    func testALegacyFileIsNamedFromItsFirstLineOnce() throws {
        let id = UUID()
        try Data("## **Plans** for `today`\n- milk".utf8).write(to: fileURL(for: id))

        let note = makeStore().note(withID: id)

        XCTAssertEqual(note?.title, "Plans for today")
        XCTAssertEqual(note?.body, "## **Plans** for `today`\n- milk", "Naming a note must never edit it")
    }

    func testALegacyFileWithNoTextIsNamedNewNote() throws {
        let id = UUID()
        try Data("".utf8).write(to: fileURL(for: id))

        XCTAssertEqual(makeStore().note(withID: id)?.title, Note.untitledTitle)
    }

    func testHandAddedFrontMatterSurvivesASave() throws {
        let id = UUID()
        try Data("---\ntitle: Kept\ntags: work\n---\nbody".utf8).write(to: fileURL(for: id))
        let store = makeStore()
        var note = try XCTUnwrap(store.note(withID: id))
        note.body = "edited"
        store.save(note)

        let text = try String(contentsOf: fileURL(for: id), encoding: .utf8)
        XCTAssertEqual(text, "---\ntitle: Kept\ntags: work\n---\nedited")
    }

    func testPreviewIsTheFirstProseLine() {
        let note = Note(
            id: UUID(),
            title: "Groceries",
            body: "- milk\n- eggs",
            createdAt: Date(),
            updatedAt: Date()
        )
        // The bullet marker goes with it: the preview is prose, not source.
        XCTAssertEqual(note.preview, "milk")
    }

    func testPreviewDoesNotEchoTheNoteName() {
        let note = Note(
            id: UUID(),
            title: "Shopping list",
            body: "# Shopping list\n- milk",
            createdAt: Date(),
            updatedAt: Date()
        )
        XCTAssertEqual(note.preview, "milk", "The tile already says the name on the line above")
    }

    func testPreviewIsPlainProse() {
        // List markers, emphasis, and link syntax are decoration: the tile
        // is describing the note, not quoting its source.
        XCTAssertEqual(
            Note(id: UUID(), body: "- **milk** and `eggs`", createdAt: Date(), updatedAt: Date()).preview,
            "milk and eggs"
        )
        XCTAssertEqual(
            Note(id: UUID(), body: "[the docs](https://example.com) explain it", createdAt: Date(), updatedAt: Date()).preview,
            "the docs explain it"
        )
    }

    func testPreviewSkipsStructuralLinesAndFlattensTables() {
        let body = """
        ---
        | Tool | Shortcut |
        | --- | --- |
        | Bold | Cmd B |
        """
        XCTAssertEqual(Note(id: UUID(), body: body, createdAt: Date(), updatedAt: Date()).preview, "Tool, Shortcut")
    }

    func testPreviewFallsBackWhenThereIsOnlyStructure() {
        let body = "```\n```\n---"
        XCTAssertEqual(Note(id: UUID(), body: body, createdAt: Date(), updatedAt: Date()).preview, "No text yet")
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
