import XCTest
@testable import Ledge

final class SessionSelectionTests: XCTestCase {
    private let favourite = SessionKind.favourite(UUID())
    private let tabA = SessionKind.tab(UUID())
    private let tabB = SessionKind.tab(UUID())

    func testClosingAMiddleSessionSelectsTheOneAfterIt() {
        XCTAssertEqual(
            SessionSelection.successor(after: favourite, in: [tabA, favourite, tabB]),
            tabB
        )
    }

    func testClosingTheFirstSessionSelectsTheNextOne() {
        XCTAssertEqual(
            SessionSelection.successor(after: tabA, in: [tabA, favourite, tabB]),
            favourite
        )
    }

    func testClosingTheLastSessionSelectsThePreviousOne() {
        XCTAssertEqual(
            SessionSelection.successor(after: tabB, in: [tabA, favourite, tabB]),
            favourite
        )
    }

    func testClosingTheOnlyOrUnknownSessionSelectsNothing() {
        XCTAssertNil(SessionSelection.successor(after: tabA, in: [tabA]))
        XCTAssertNil(SessionSelection.successor(after: tabB, in: [tabA, favourite]))
    }

    func testSessionKindAccessorsKeepAssociationExplicit() {
        let siteID = UUID()
        let tabID = UUID()
        XCTAssertEqual(SessionKind.favourite(siteID).favouriteID, siteID)
        XCTAssertNil(SessionKind.favourite(siteID).tabID)
        XCTAssertEqual(SessionKind.tab(tabID).tabID, tabID)
        XCTAssertNil(SessionKind.tab(tabID).favouriteID)
    }
}
