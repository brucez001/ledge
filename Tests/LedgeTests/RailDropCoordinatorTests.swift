import XCTest
@testable import Ledge

@MainActor
final class RailDropCoordinatorTests: XCTestCase {

    private let siteA = UUID()
    private let tabA = UUID()
    private let tabB = UUID()

    private var entries: [RailEntry] {
        [.favourite(siteA), .tab(tabA), .tab(tabB)]
    }

    func testNoLineIsShownUntilADragBegins() {
        let coordinator = RailDropCoordinator()

        coordinator.pointerMoved(over: .tab(tabA), isBelow: true, in: entries)

        XCTAssertNil(coordinator.line)
    }

    func testLineFollowsThePointerOnceADragBegins() {
        let coordinator = RailDropCoordinator()
        coordinator.begin(dragging: .tab(tabB))

        coordinator.pointerMoved(over: .favourite(siteA), isBelow: true, in: entries)
        XCTAssertTrue(coordinator.showsLine(for: .favourite(siteA), isBelow: true))
        XCTAssertFalse(coordinator.showsLine(for: .favourite(siteA), isBelow: false))

        coordinator.pointerMoved(over: .favourite(siteA), isBelow: false, in: entries)
        XCTAssertTrue(coordinator.showsLine(for: .favourite(siteA), isBelow: false))
    }

    /// SwiftUI can deliver the previous row's exit after the next row's enter.
    /// A stale exit must not wipe the line the newer row has already claimed,
    /// or the indicator flickers off mid-drag.
    func testStaleExitFromAPreviouslyHoveredRowIsIgnored() {
        let coordinator = RailDropCoordinator()
        coordinator.begin(dragging: .tab(tabB))

        // Above the first row: the line goes on top of the rail.
        coordinator.pointerMoved(over: .favourite(siteA), isBelow: false, in: entries)
        XCTAssertTrue(coordinator.showsLine(for: .favourite(siteA), isBelow: false))

        // Then above the middle row, which lands the dragged row after the
        // first one instead: a different line, so a stale clear would show.
        coordinator.pointerMoved(over: .tab(tabA), isBelow: false, in: entries)
        coordinator.pointerLeft(.favourite(siteA))

        XCTAssertTrue(coordinator.showsLine(for: .favourite(siteA), isBelow: true))
    }

    func testLeavingTheRowUnderThePointerClearsTheLine() {
        let coordinator = RailDropCoordinator()
        coordinator.begin(dragging: .tab(tabB))
        coordinator.pointerMoved(over: .tab(tabA), isBelow: true, in: entries)

        coordinator.pointerLeft(.tab(tabA))

        XCTAssertNil(coordinator.line)
    }

    /// Ending the drag must also forget which row was dragged, so a later
    /// pointer move cannot resurrect a line without a fresh drag.
    func testEndingTheDragClearsEverything() {
        let coordinator = RailDropCoordinator()
        coordinator.begin(dragging: .tab(tabB))
        coordinator.pointerMoved(over: .tab(tabA), isBelow: true, in: entries)

        coordinator.end()
        XCTAssertNil(coordinator.line)

        coordinator.pointerMoved(over: .tab(tabA), isBelow: true, in: entries)
        XCTAssertNil(coordinator.line)
    }

    func testHoveringTheDraggedRowItselfShowsNoLine() {
        let coordinator = RailDropCoordinator()
        coordinator.begin(dragging: .tab(tabA))

        coordinator.pointerMoved(over: .tab(tabA), isBelow: false, in: entries)

        XCTAssertNil(coordinator.line)
    }
}
