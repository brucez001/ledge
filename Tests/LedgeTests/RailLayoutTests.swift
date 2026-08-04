import XCTest
@testable import Ledge

final class RailLayoutTests: XCTestCase {
    private let siteA = UUID(), siteB = UUID(), siteC = UUID()
    private let tab1 = UUID(), tab2 = UUID()

    // MARK: - Building the rail

    /// The historical layout, and still the default: a tab with no placement of
    /// its own sits after the saved sites.
    func testTabsWithoutAnchorsFollowTheSavedSites() {
        XCTAssertEqual(
            RailLayout.entries(favourites: [siteA, siteB], tabs: [tab1], anchors: [:]),
            [.favourite(siteA), .favourite(siteB), .tab(tab1)]
        )
    }

    /// The point of the whole exercise: a tab can hold a position among the
    /// saved sites without becoming one.
    func testATabCanSitBetweenTwoSavedSites() {
        XCTAssertEqual(
            RailLayout.entries(
                favourites: [siteA, siteB],
                tabs: [tab1],
                anchors: [tab1: .after(siteA)]
            ),
            [.favourite(siteA), .tab(tab1), .favourite(siteB)]
        )
    }

    func testATabCanSitAboveEverySavedSite() {
        XCTAssertEqual(
            RailLayout.entries(favourites: [siteA], tabs: [tab1], anchors: [tab1: .start]),
            [.tab(tab1), .favourite(siteA)]
        )
    }

    func testTabsSharingAnAnchorKeepTheirGivenOrder() {
        XCTAssertEqual(
            RailLayout.entries(
                favourites: [siteA],
                tabs: [tab2, tab1],
                anchors: [tab1: .after(siteA), tab2: .after(siteA)]
            ),
            [.favourite(siteA), .tab(tab2), .tab(tab1)]
        )
    }

    /// An anchor is relative, so reordering the saved sites carries the tab
    /// along with the one it was placed after. An absolute index could not.
    func testATabFollowsTheSiteItIsAnchoredToWhenSitesAreReordered() {
        let anchors: [UUID: RailAnchor] = [tab1: .after(siteA)]
        XCTAssertEqual(
            RailLayout.entries(favourites: [siteB, siteA], tabs: [tab1], anchors: anchors),
            [.favourite(siteB), .favourite(siteA), .tab(tab1)]
        )
    }

    /// Last-resort fallback only: an anchor referring to a site that is not in
    /// the list at all (a stale anchor no removal path produced) still yields a
    /// valid rail rather than losing the tab. Deletion itself re-homes the tab
    /// onto the row above -- see `testRemovingASiteRehomesTheTabAboveIt`.
    func testATabAnchoredToAnUnknownSiteFallsBackToTheEnd() {
        XCTAssertEqual(
            RailLayout.entries(
                favourites: [siteB],
                tabs: [tab1],
                anchors: [tab1: .after(siteC)]
            ),
            [.favourite(siteB), .tab(tab1)]
        )
    }

    func testTabsSurviveWithNoSavedSitesAtAll() {
        XCTAssertEqual(
            RailLayout.entries(favourites: [], tabs: [tab1, tab2], anchors: [:]),
            [.tab(tab1), .tab(tab2)]
        )
    }

    // MARK: - Moving by drop position

    func testDroppingASiteOnTheUpperHalfOfARowInsertsAboveIt() {
        let entries: [RailEntry] = [.favourite(siteA), .favourite(siteB), .tab(tab1)]
        XCTAssertEqual(
            RailLayout.moved(.favourite(siteB), relativeTo: .favourite(siteA), isBelow: false, in: entries),
            [.favourite(siteB), .favourite(siteA), .tab(tab1)]
        )
    }

    /// A tab moving up over a saved site: allowed, and it stays a tab.
    func testATabCanBeDroppedAboveASavedSite() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tab1)]
        XCTAssertEqual(
            RailLayout.moved(.tab(tab1), relativeTo: .favourite(siteA), isBelow: false, in: entries),
            [.tab(tab1), .favourite(siteA)]
        )
    }

    /// With no insertion indicator drawn, a drop resolving to "stay put" looks
    /// like a failed drag, so the other side of the target is used instead.
    func testDroppingWhereTheRowAlreadySitsFallsBackToTheOtherSide() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tab1)]
        XCTAssertEqual(
            RailLayout.moved(.tab(tab1), relativeTo: .favourite(siteA), isBelow: true, in: entries),
            [.tab(tab1), .favourite(siteA)]
        )
    }

    func testDroppingARowOnItselfChangesNothing() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tab1)]
        XCTAssertNil(RailLayout.moved(.tab(tab1), relativeTo: .tab(tab1), isBelow: true, in: entries))
    }

    func testDroppingOnAnUnknownTargetIsRefused() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tab1)]
        XCTAssertNil(
            RailLayout.moved(.tab(tab1), relativeTo: .favourite(siteC), isBelow: true, in: entries)
        )
    }

    // MARK: - Moving by menu

    func testMoveUpStepsOverTheRowAboveWhateverKindItIs() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tab1), .favourite(siteB)]
        XCTAssertEqual(
            RailLayout.moved(.tab(tab1), by: -1, in: entries),
            [.tab(tab1), .favourite(siteA), .favourite(siteB)]
        )
        XCTAssertEqual(
            RailLayout.moved(.favourite(siteB), by: -1, in: entries),
            [.favourite(siteA), .favourite(siteB), .tab(tab1)]
        )
    }

    func testMovingBeyondEitherEndIsRefused() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tab1)]
        XCTAssertNil(RailLayout.moved(.favourite(siteA), by: -1, in: entries))
        XCTAssertNil(RailLayout.moved(.tab(tab1), by: 1, in: entries))
    }

    func testMovingAnUnknownRowIsRefused() {
        XCTAssertNil(RailLayout.moved(.tab(tab2), by: -1, in: [.favourite(siteA), .tab(tab1)]))
    }

    // MARK: - Projecting back onto the stores

    func testFavouriteAndTabOrdersAreReadBackOut() {
        let entries: [RailEntry] = [.tab(tab1), .favourite(siteA), .favourite(siteB), .tab(tab2)]
        XCTAssertEqual(RailLayout.favourites(in: entries), [siteA, siteB])
        XCTAssertEqual(RailLayout.tabs(in: entries), [tab1, tab2])
    }

    func testAnchorsAreDerivedFromTheNearestSiteAbove() {
        let entries: [RailEntry] = [.tab(tab1), .favourite(siteA), .tab(tab2), .favourite(siteB)]
        XCTAssertEqual(RailLayout.anchors(in: entries), [tab1: .start, tab2: .after(siteA)])
    }

    // MARK: - Removing and replacing rows

    /// Deleting the site a tab sits under must leave the tab where it is, not
    /// drop it to the end of the rail.
    func testRemovingASiteRehomesTheTabAboveIt() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tab1), .favourite(siteB)]
        let remaining = RailLayout.removing(.favourite(siteA), from: entries)

        XCTAssertEqual(remaining, [.tab(tab1), .favourite(siteB)])
        XCTAssertEqual(RailLayout.anchors(in: remaining), [tab1: .start])
        XCTAssertEqual(
            RailLayout.entries(
                favourites: [siteB],
                tabs: [tab1],
                anchors: RailLayout.anchors(in: remaining)
            ),
            [.tab(tab1), .favourite(siteB)]
        )
    }

    /// Keeping a tab must preserve its exact row, including its position among
    /// other tabs sharing the same anchor -- carrying the anchor alone would drop
    /// it behind its neighbours.
    func testKeepingATabPreservesItsPositionWithinItsCohort() {
        let entries: [RailEntry] = [
            .favourite(siteA), .tab(tab1), .tab(tab2), .favourite(siteB)
        ]
        let pinned = UUID()
        let replaced = RailLayout.replacing(.tab(tab1), with: .favourite(pinned), in: entries)

        XCTAssertEqual(
            replaced,
            [.favourite(siteA), .favourite(pinned), .tab(tab2), .favourite(siteB)]
        )
        XCTAssertEqual(RailLayout.favourites(in: replaced), [siteA, pinned, siteB])
        XCTAssertEqual(RailLayout.anchors(in: replaced), [tab2: .after(pinned)])

        // And it survives the rebuild, rather than only looking right once.
        XCTAssertEqual(
            RailLayout.entries(
                favourites: RailLayout.favourites(in: replaced),
                tabs: RailLayout.tabs(in: replaced),
                anchors: RailLayout.anchors(in: replaced)
            ),
            replaced
        )
    }

    /// A tab kept while sitting above every saved site stays at the top.
    func testKeepingATabAtTheTopOfTheRailStaysAtTheTop() {
        let entries: [RailEntry] = [.tab(tab1), .favourite(siteA)]
        let pinned = UUID()
        XCTAssertEqual(
            RailLayout.replacing(.tab(tab1), with: .favourite(pinned), in: entries),
            [.favourite(pinned), .favourite(siteA)]
        )
    }

    func testRemovingARowThatIsNotThereChangesNothing() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tab1)]
        XCTAssertEqual(RailLayout.removing(.favourite(siteC), from: entries), entries)
    }

    /// Building, moving, and projecting must round-trip: the order a move
    /// produces is the order the rail then shows.
    func testAMoveRoundTripsThroughTheStores() {
        let entries = RailLayout.entries(favourites: [siteA, siteB], tabs: [tab1], anchors: [:])

        guard let moved = RailLayout.moved(.tab(tab1), by: -2, in: entries) else {
            return XCTFail("expected the tab to move to the top of the rail")
        }

        let rebuilt = RailLayout.entries(
            favourites: RailLayout.favourites(in: moved),
            tabs: RailLayout.tabs(in: moved),
            anchors: RailLayout.anchors(in: moved)
        )
        XCTAssertEqual(rebuilt, moved)
        XCTAssertEqual(rebuilt, [.tab(tab1), .favourite(siteA), .favourite(siteB)])
    }
}
