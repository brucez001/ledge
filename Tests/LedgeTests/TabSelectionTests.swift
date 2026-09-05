import XCTest
@testable import Ledge

final class RailSelectionTests: XCTestCase {
    private let favourite = RailEntry.favourite(UUID())
    private let tab = RailEntry.tab(UUID())
    private let note = RailEntry.note(UUID())

    func testClosingAMiddleItemSelectsTheOneAfterIt() {
        XCTAssertEqual(
            RailSelection.successor(after: favourite, in: [tab, favourite, note]),
            note
        )
    }

    func testClosingTheFirstItemSelectsTheNextOne() {
        XCTAssertEqual(
            RailSelection.successor(after: tab, in: [tab, favourite, note]),
            favourite
        )
    }

    func testClosingTheLastItemSelectsThePreviousOne() {
        XCTAssertEqual(
            RailSelection.successor(after: note, in: [tab, favourite, note]),
            favourite
        )
    }

    func testClosingTheOnlyOrUnknownItemSelectsNothing() {
        XCTAssertNil(RailSelection.successor(after: tab, in: [tab]))
        XCTAssertNil(RailSelection.successor(after: note, in: [tab, favourite]))
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
