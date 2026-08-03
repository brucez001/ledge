import XCTest
@testable import Ledge

final class TabSelectionTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testClosingAMiddleTabSelectsTheOneAfterIt() {
        XCTAssertEqual(TabSelection.successor(after: b, in: [a, b, c]), c)
    }

    func testClosingTheFirstTabSelectsTheNextOne() {
        XCTAssertEqual(TabSelection.successor(after: a, in: [a, b, c]), b)
    }

    /// Nothing slides into the last slot, so selection falls back to the tab
    /// before it rather than off the end of the list.
    func testClosingTheLastTabSelectsThePreviousOne() {
        XCTAssertEqual(TabSelection.successor(after: c, in: [a, b, c]), b)
    }

    func testClosingTheOnlyTabLeavesNothingSelected() {
        XCTAssertNil(TabSelection.successor(after: a, in: [a]))
    }

    func testClosingAnUnknownTabSelectsNothing() {
        XCTAssertNil(TabSelection.successor(after: UUID(), in: [a, b]))
    }

    func testEmptyListSelectsNothing() {
        XCTAssertNil(TabSelection.successor(after: a, in: []))
    }

    func testSessionKindTabIDOnlyUnwrapsTabs() {
        XCTAssertEqual(SessionKind.tab(a).tabID, a)
        XCTAssertNil(SessionKind.favourite(a).tabID)
    }

    /// Tabs and saved sites must never collide in the session dictionary even
    /// if they somehow shared a UUID.
    func testTabAndFavouriteKindsAreDistinct() {
        XCTAssertNotEqual(SessionKind.tab(a), SessionKind.favourite(a))
        var seen: Set<SessionKind> = []
        seen.insert(.tab(a))
        seen.insert(.favourite(a))
        XCTAssertEqual(seen.count, 2)
    }
}
