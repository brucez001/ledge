import XCTest
@testable import Ledge

final class RailLayoutTests: XCTestCase {
    private let siteA = UUID()
    private let siteB = UUID()
    private let tabA = UUID()
    private let tabB = UUID()

    func testNumberedShortcutCountsRailRowsFromTheTop() {
        let note = UUID()
        let entries: [RailEntry] = [.tab(tabA), .note(note), .favourite(siteA)]
        XCTAssertEqual(RailLayout.entry(numbered: 1, in: entries), .tab(tabA))
        XCTAssertEqual(RailLayout.entry(numbered: 2, in: entries), .note(note))
        XCTAssertEqual(RailLayout.entry(numbered: 3, in: entries), .favourite(siteA))
    }

    func testNumberedShortcutFollowsRailOrderRatherThanFavouriteOrder() {
        let entries: [RailEntry] = [.favourite(siteB), .favourite(siteA)]
        XCTAssertEqual(RailLayout.entry(numbered: 1, in: entries), .favourite(siteB))
        XCTAssertEqual(RailLayout.entry(numbered: 2, in: entries), .favourite(siteA))
    }

    func testNumberedShortcutBeyondTheRailDoesNothing() {
        let entries: [RailEntry] = [.tab(tabA), .tab(tabB)]
        XCTAssertNil(RailLayout.entry(numbered: 3, in: entries))
        XCTAssertNil(RailLayout.entry(numbered: 0, in: entries))
        XCTAssertNil(RailLayout.entry(numbered: 1, in: []))
    }

    func testDroppingAboveInsertsAboveTarget() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA), .tab(tabB)]
        XCTAssertEqual(
            RailLayout.moved(.tab(tabB), relativeTo: .favourite(siteA), isBelow: false, in: entries),
            [.tab(tabB), .favourite(siteA), .tab(tabA)]
        )
    }

    func testDroppingBelowInsertsBelowTarget() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA), .tab(tabB)]
        XCTAssertEqual(
            RailLayout.moved(.favourite(siteA), relativeTo: .tab(tabB), isBelow: true, in: entries),
            [.tab(tabA), .tab(tabB), .favourite(siteA)]
        )
    }

    func testDroppingOnTheSideThatLooksUnchangedUsesTheOtherSide() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA), .tab(tabB)]
        XCTAssertEqual(
            RailLayout.moved(.tab(tabA), relativeTo: .favourite(siteA), isBelow: true, in: entries),
            [.tab(tabA), .favourite(siteA), .tab(tabB)]
        )
    }

    func testDroppingARowOnItselfOrUnknownTargetIsRefused() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA)]
        XCTAssertNil(RailLayout.moved(.tab(tabA), relativeTo: .tab(tabA), isBelow: true, in: entries))
        XCTAssertNil(RailLayout.moved(.tab(tabA), relativeTo: .tab(tabB), isBelow: true, in: entries))
    }

    func testMoveByOffsetWorksAcrossFavouriteAssociation() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA), .favourite(siteB)]
        XCTAssertEqual(
            RailLayout.moved(.favourite(siteB), by: -2, in: entries),
            [.favourite(siteB), .favourite(siteA), .tab(tabA)]
        )
    }

    func testMovingBeyondAnEndOrMovingUnknownRowIsRefused() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA)]
        XCTAssertNil(RailLayout.moved(.favourite(siteA), by: -1, in: entries))
        XCTAssertNil(RailLayout.moved(.tab(tabA), by: 1, in: entries))
        XCTAssertNil(RailLayout.moved(.tab(tabB), by: -1, in: entries))
    }

    // MARK: - Drop indicator

    func testInsertionLineSitsBelowTheRowTheDraggedRowWillFollow() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA), .favourite(siteB)]
        XCTAssertEqual(
            RailLayout.insertionLine(
                dragging: .favourite(siteA),
                over: .tab(tabA),
                isBelow: true,
                in: entries
            ),
            RailDropLine(entry: .tab(tabA), isBelow: true)
        )
    }

    /// Landing at the very top has no preceding row, so the line has to be
    /// anchored above the row that will follow instead.
    func testInsertionLineAnchorsAboveTheFirstRowWhenLandingAtTheTop() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA), .favourite(siteB)]
        XCTAssertEqual(
            RailLayout.insertionLine(
                dragging: .favourite(siteB),
                over: .favourite(siteA),
                isBelow: false,
                in: entries
            ),
            RailDropLine(entry: .favourite(siteA), isBelow: false)
        )
    }

    /// `moved` flips to the opposite side when the pointer's own side would be
    /// a no-op. The line must follow the flip, not the pointer, or it would
    /// promise a position the drop does not honour.
    func testInsertionLineFollowsTheFlippedSideRatherThanThePointer() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA)]
        // Dropping `tabA` below `siteA` is where it already is, so the drop
        // resolves to "above" and the line belongs at the top of the rail.
        XCTAssertEqual(
            RailLayout.insertionLine(
                dragging: .tab(tabA),
                over: .favourite(siteA),
                isBelow: true,
                in: entries
            ),
            RailDropLine(entry: .favourite(siteA), isBelow: false)
        )
    }

    func testNoInsertionLineWhenTheDropWouldChangeNothing() {
        let entries: [RailEntry] = [.favourite(siteA), .tab(tabA)]
        // Hovering a row over itself, and an unknown row, are both no-ops.
        XCTAssertNil(
            RailLayout.insertionLine(
                dragging: .tab(tabA),
                over: .tab(tabA),
                isBelow: true,
                in: entries
            )
        )
        XCTAssertNil(
            RailLayout.insertionLine(
                dragging: .tab(tabB),
                over: .tab(tabA),
                isBelow: false,
                in: entries
            )
        )
    }

    func testSingleRowRailNeverShowsALine() {
        let entries: [RailEntry] = [.favourite(siteA)]
        XCTAssertNil(
            RailLayout.insertionLine(
                dragging: .favourite(siteA),
                over: .favourite(siteA),
                isBelow: true,
                in: entries
            )
        )
    }
}
