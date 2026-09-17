import XCTest
@testable import Ledge

/// Covers the Home grid's user-arranged note order: its default, what a stale
/// stored order may not do, and that arranging survives a reload.
@MainActor
final class NoteOrderTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LedgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> NoteStore {
        NoteStore(directory: directory, defaults: defaults)
    }

    private func note(_ title: String, updatedAt: Date) -> Note {
        Note(id: UUID(), title: title, body: "", createdAt: updatedAt, updatedAt: updatedAt)
    }

    // MARK: - Default

    func testWithNoStoredOrderNotesFallBackToMostRecentlyEditedFirst() {
        let older = note("Older", updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = note("Newer", updatedAt: Date(timeIntervalSince1970: 2_000))

        let ordered = NoteStore.ordered([older, newer], by: [])

        XCTAssertEqual(ordered.map(\.title), ["Newer", "Older"])
    }

    // MARK: - Invalid and stale stored values

    func testIdsForNotesThatNoLongerExistAreIgnored() {
        let kept = note("Kept", updatedAt: Date(timeIntervalSince1970: 1_000))

        let ordered = NoteStore.ordered([kept], by: [UUID(), kept.id, UUID()])

        XCTAssertEqual(ordered.map(\.title), ["Kept"])
    }

    /// A stale order must never hide a note: one created since the last
    /// arrangement still appears, after the arranged ones.
    func testNotesMissingFromTheStoredOrderStillAppearMostRecentFirst() {
        let arranged = note("Arranged", updatedAt: Date(timeIntervalSince1970: 1_000))
        let olderUnlisted = note("Older unlisted", updatedAt: Date(timeIntervalSince1970: 2_000))
        let newerUnlisted = note("Newer unlisted", updatedAt: Date(timeIntervalSince1970: 3_000))

        let ordered = NoteStore.ordered(
            [olderUnlisted, arranged, newerUnlisted],
            by: [arranged.id]
        )

        XCTAssertEqual(ordered.map(\.title), ["Arranged", "Newer unlisted", "Older unlisted"])
    }

    func testADuplicatedIdInTheStoredOrderDoesNotTrap() {
        let first = note("First", updatedAt: Date(timeIntervalSince1970: 1_000))
        let second = note("Second", updatedAt: Date(timeIntervalSince1970: 2_000))

        let ordered = NoteStore.ordered([second, first], by: [first.id, first.id, second.id])

        XCTAssertEqual(ordered.map(\.title), ["First", "Second"])
    }

    // MARK: - Arranging

    func testMovingANoteBeforeAnotherReordersTheGrid() {
        let store = makeStore()
        let first = store.createNewNote()
        let second = store.createNewNote()
        let third = store.createNewNote()
        // Newest first, so creation order reverses.
        XCTAssertEqual(store.notes.map(\.id), [third.id, second.id, first.id])

        store.move(id: third.id, before: first.id)

        XCTAssertEqual(store.notes.map(\.id), [second.id, third.id, first.id])
    }

    func testMovingANoteToTheEndReachesTheLastPosition() {
        let store = makeStore()
        let first = store.createNewNote()
        let second = store.createNewNote()

        store.moveToEnd(id: second.id)

        XCTAssertEqual(store.notes.map(\.id), [first.id, second.id])
    }

    func testAnArrangedGridSurvivesReload() {
        let store = makeStore()
        let first = store.createNewNote()
        let second = store.createNewNote()
        store.move(id: first.id, before: second.id)
        let expected = store.notes.map(\.id)

        XCTAssertEqual(makeStore().notes.map(\.id), expected)
    }

    /// The reason to arrange a grid at all: editing a note must not move its
    /// tile back to the front.
    func testEditingAnArrangedNoteDoesNotMoveItsTile() {
        let store = makeStore()
        let first = store.createNewNote()
        let second = store.createNewNote()
        store.move(id: first.id, before: second.id)

        var edited = store.note(withID: second.id)!
        edited.body = "edited"
        store.save(edited)

        XCTAssertEqual(store.notes.map(\.id), [first.id, second.id])
    }

    func testANewNoteJoinsAnArrangedGridAtTheFrontRatherThanTheBack() {
        let store = makeStore()
        let first = store.createNewNote()
        let second = store.createNewNote()
        store.move(id: first.id, before: second.id)

        let fresh = store.createNewNote()

        XCTAssertEqual(store.notes.map(\.id), [fresh.id, first.id, second.id])
    }

    func testDeletingAnArrangedNoteDropsItFromTheOrder() {
        let store = makeStore()
        let first = store.createNewNote()
        let second = store.createNewNote()
        store.move(id: first.id, before: second.id)

        store.delete(first)

        XCTAssertEqual(store.notes.map(\.id), [second.id])
        XCTAssertEqual(makeStore().notes.map(\.id), [second.id])
    }
}
