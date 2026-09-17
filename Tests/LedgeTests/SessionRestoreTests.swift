import XCTest
@testable import Ledge

/// The point of restoring lazily: rows come back, pages do not.
@MainActor
final class SessionRestoreTests: XCTestCase {
    private func session(favouriteID: UUID? = nil, url: String) -> OpenSessionsStore.OpenSession {
        OpenSessionsStore.OpenSession(
            favouriteID: favouriteID,
            url: URL(string: url)!,
            title: "Example",
            iconHost: "example.com"
        )
    }

    func testRestoredSessionsAppearInTheRailInOrder() {
        let manager = SessionManager()

        manager.restore([session(url: "https://one.test"), session(url: "https://two.test")])

        XCTAssertEqual(
            manager.sessions.map(\.currentURL?.host),
            ["one.test", "two.test"]
        )
    }

    /// The whole feature: restoring must not build a web view or fetch
    /// anything. Ledge launches at login.
    func testRestoringDoesNotBuildWebViews() {
        let manager = SessionManager()

        manager.restore([session(url: "https://one.test"), session(url: "https://two.test")])

        XCTAssertTrue(manager.sessions.allSatisfy { !$0.isMaterialised })
    }

    func testARestoredSessionKeepsItsTitleAndIconBeforeItLoads() {
        let manager = SessionManager()

        manager.restore([session(url: "https://one.test")])

        XCTAssertEqual(manager.sessions.first?.pageTitle, "Example")
        XCTAssertEqual(manager.sessions.first?.iconHost, "example.com")
    }

    func testARestoredFavouriteSessionKeepsItsFavouriteAssociation() {
        let manager = SessionManager()
        let favouriteID = UUID()

        manager.restore([session(favouriteID: favouriteID, url: "https://one.test")])

        XCTAssertEqual(manager.sessions.first?.id, .favourite(favouriteID))
    }

    func testRestoreIsIgnoredOnceSessionsAreOpen() {
        let manager = SessionManager()
        manager.restore([session(url: "https://one.test")])

        manager.restore([session(url: "https://two.test")])

        XCTAssertEqual(manager.sessions.count, 1)
    }

    func testASessionWithNothingLoadedIsNotWorthRestoring() {
        let manager = SessionManager()
        manager.newTabSession()

        XCTAssertTrue(manager.restorableSessions.isEmpty)
    }

    func testRestoredRowsAreThemselvesRestorableAgain() {
        let manager = SessionManager()
        let saved = [session(url: "https://one.test"), session(url: "https://two.test")]

        manager.restore(saved)

        XCTAssertEqual(manager.restorableSessions, saved)
    }
}
