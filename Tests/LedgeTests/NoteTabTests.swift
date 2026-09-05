import XCTest
@testable import Ledge

@MainActor
final class NoteTabTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeController() -> NoteController {
        NoteController(store: NoteStore(directory: directory))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("md")
    }

    func testOpenNewNoteCreatesATabAndAFile() {
        let controller = makeController()
        let tab = controller.openNewNote()

        XCTAssertEqual(controller.tabs.map(\.id), [tab.note.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL(for: tab.note.id).path))
        XCTAssertTrue(controller.openNoteIDs.contains(tab.note.id))
    }

    func testOpenReusesTheExistingTab() {
        let controller = makeController()
        let tab = controller.openNewNote()

        XCTAssertTrue(controller.open(tab.note) === tab)
        XCTAssertEqual(controller.tabs.count, 1)
    }

    func testCloseSavesTheDraftAndKeepsTheFile() {
        let controller = makeController()
        let tab = controller.openNewNote()
        tab.body = "Shopping list\nmilk"
        tab.bodyDidChange()

        controller.close(tab.note.id)

        XCTAssertTrue(controller.tabs.isEmpty)
        XCTAssertEqual(controller.store.note(withID: tab.note.id)?.body, "Shopping list\nmilk")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL(for: tab.note.id).path))
    }

    func testDeleteRemovesTheFileAndTheTab() {
        let controller = makeController()
        let tab = controller.openNewNote()
        tab.body = "gone soon"
        tab.bodyDidChange()

        controller.delete(tab.note.id)

        XCTAssertTrue(controller.tabs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL(for: tab.note.id).path))
        XCTAssertNil(makeController().store.note(withID: tab.note.id))
    }

    func testSetNoteOrderReordersTabs() {
        let controller = makeController()
        let first = controller.openNewNote()
        let second = controller.openNewNote()

        controller.setNoteOrder([second.note.id, first.note.id])

        XCTAssertEqual(controller.tabs.map(\.id), [second.note.id, first.note.id])
    }

    func testSetNoteOrderIgnoresAStalePermutation() {
        let controller = makeController()
        let first = controller.openNewNote()
        _ = controller.openNewNote()

        controller.setNoteOrder([UUID(), first.note.id])

        XCTAssertEqual(controller.tabs.count, 2)
    }

    func testSaveAllOpenFlushesEveryDraft() {
        let controller = makeController()
        let tab = controller.openNewNote()
        tab.body = "draft only"

        controller.saveAllOpen()

        XCTAssertEqual(controller.store.note(withID: tab.note.id)?.body, "draft only")
    }

    func testTabsOpenReadyToEditAndTogglePreviewPerTab() {
        let controller = makeController()
        let first = controller.openNewNote()
        let second = controller.openNewNote()

        XCTAssertFalse(first.isPreviewing)
        XCTAssertFalse(second.isPreviewing)

        first.togglePreview()

        XCTAssertTrue(first.isPreviewing)
        XCTAssertFalse(second.isPreviewing)

        first.togglePreview()

        XCTAssertFalse(first.isPreviewing)
    }

    func testTogglingPreviewLeavesTheDraftAlone() {
        let controller = makeController()
        let tab = controller.openNewNote()
        tab.body = "# Heading"

        tab.togglePreview()

        XCTAssertEqual(tab.body, "# Heading")
        XCTAssertTrue(tab.isPreviewing)
    }

    func testRenameLeavesTheMarkdownAlone() {
        let controller = makeController()
        let tab = controller.openNewNote()
        tab.body = "# Old heading\n\n- milk"
        tab.bodyDidChange()

        tab.rename(to: "Shopping")

        XCTAssertEqual(tab.body, "# Old heading\n\n- milk", "A note's name is not its first line")
        XCTAssertEqual(tab.note.title, "Shopping")
    }

    func testTypingAHeadingDoesNotRenameTheNote() {
        let controller = makeController()
        let tab = controller.openNewNote()
        tab.rename(to: "Shopping")

        tab.body = "## haha\nmilk"
        tab.bodyDidChange()

        XCTAssertEqual(tab.note.title, "Shopping")
    }

    func testRenamePersistsAfterTheTabIsClosed() {
        let controller = makeController()
        let tab = controller.openNewNote()

        tab.rename(to: "Named on creation")
        controller.close(tab.note.id)

        XCTAssertEqual(controller.store.note(withID: tab.note.id)?.title, "Named on creation")
        XCTAssertEqual(controller.store.note(withID: tab.note.id)?.body, "")
    }

    func testRenameKeepsTheDraftThatIsOnScreen() {
        let controller = makeController()
        let tab = controller.openNewNote()
        tab.body = "typed but not yet autosaved"

        tab.rename(to: "Draft")

        XCTAssertEqual(controller.store.note(withID: tab.note.id)?.body, "typed but not yet autosaved")
    }

    func testRenameToBlankKeepsTheName() {
        let controller = makeController()
        let tab = controller.openNewNote()
        tab.rename(to: "Keep me")

        tab.rename(to: "  ")

        XCTAssertEqual(tab.note.title, "Keep me")
    }

}
