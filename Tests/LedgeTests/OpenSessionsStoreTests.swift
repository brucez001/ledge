import XCTest
@testable import Ledge

/// Covers what survives a quit and what a stale record may not do.
@MainActor
final class OpenSessionsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "LedgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func session(favouriteID: UUID? = nil, url: String = "https://example.com") -> OpenSessionsStore.OpenSession {
        OpenSessionsStore.OpenSession(
            favouriteID: favouriteID,
            url: URL(string: url)!,
            title: "Example",
            iconHost: "example.com"
        )
    }

    // MARK: - Persistence

    func testSessionsSurviveARoundTrip() {
        let store = OpenSessionsStore(defaults: defaults)
        let saved = [session(favouriteID: UUID()), session(url: "https://other.test")]

        store.saveSessions(saved)

        XCTAssertEqual(OpenSessionsStore(defaults: defaults).loadSessions(), saved)
    }

    func testNoStoredSessionsRestoresAnEmptyRail() {
        XCTAssertTrue(OpenSessionsStore(defaults: defaults).loadSessions().isEmpty)
    }

    func testUnreadableStoredSessionsRestoreAnEmptyRailRatherThanTrapping() {
        defaults.set(Data("not json".utf8), forKey: "ledge.openSessions")

        XCTAssertTrue(OpenSessionsStore(defaults: defaults).loadSessions().isEmpty)
    }

    func testNoteTabsSurviveARoundTrip() {
        let store = OpenSessionsStore(defaults: defaults)
        let ids = [UUID(), UUID()]

        store.saveNoteTabs(ids)

        XCTAssertEqual(OpenSessionsStore(defaults: defaults).loadNoteTabs(), ids)
    }

    // MARK: - Reconciliation

    func testASessionWhoseFavouriteStillExistsIsRestoredAsIs() {
        let id = UUID()

        let reconciled = OpenSessionsStore.reconciled([session(favouriteID: id)], against: [id])

        XCTAssertEqual(reconciled.first?.favouriteID, id)
    }

    /// A restored row must never point at a favourite that has been deleted
    /// since: it stays in the rail, but as an ordinary tab.
    func testASessionWhoseFavouriteWasDeletedBecomesAnOrdinaryTab() {
        let reconciled = OpenSessionsStore.reconciled([session(favouriteID: UUID())], against: [])

        XCTAssertEqual(reconciled.count, 1)
        XCTAssertNil(reconciled.first?.favouriteID)
        XCTAssertEqual(reconciled.first?.url, URL(string: "https://example.com"))
    }

    func testNoteTabsForDeletedNotesAreDropped() {
        let kept = UUID()

        XCTAssertEqual(
            OpenSessionsStore.reconciledNoteTabs([kept, UUID()], against: [kept]),
            [kept]
        )
    }
}
