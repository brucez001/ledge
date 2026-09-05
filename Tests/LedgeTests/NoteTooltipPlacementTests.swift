import XCTest
@testable import Ledge

final class NoteTooltipPlacementTests: XCTestCase {
    private let container = CGSize(width: 400, height: 300)
    private let tooltip = CGSize(width: 120, height: 24)

    func testSitsBelowAndCentredOnTheControl() {
        let control = CGRect(x: 180, y: 10, width: 26, height: 24)

        let origin = NoteTooltipPlacement.origin(control: control, container: container, tooltip: tooltip)

        XCTAssertEqual(origin.x, control.midX - tooltip.width / 2, accuracy: 0.001)
        XCTAssertEqual(origin.y, control.maxY + NoteTooltipPlacement.gap, accuracy: 0.001)
    }

    func testClampsToTheLeftMargin() {
        let control = CGRect(x: 0, y: 10, width: 26, height: 24)

        let origin = NoteTooltipPlacement.origin(control: control, container: container, tooltip: tooltip)

        XCTAssertEqual(origin.x, NoteTooltipPlacement.margin, accuracy: 0.001)
    }

    func testClampsToTheRightMargin() {
        // The delete button sits hard against the pane's trailing edge.
        let control = CGRect(x: 374, y: 10, width: 26, height: 24)

        let origin = NoteTooltipPlacement.origin(control: control, container: container, tooltip: tooltip)

        XCTAssertEqual(
            origin.x,
            container.width - tooltip.width - NoteTooltipPlacement.margin,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(origin.x + tooltip.width, container.width)
    }

    func testFlipsAboveWhenThereIsNoRoomBelow() {
        let control = CGRect(x: 180, y: 260, width: 26, height: 24)

        let origin = NoteTooltipPlacement.origin(control: control, container: container, tooltip: tooltip)

        XCTAssertEqual(
            origin.y,
            control.minY - NoteTooltipPlacement.gap - tooltip.height,
            accuracy: 0.001
        )
    }

    func testNeverGoesAboveTheTopMargin() {
        // Squeezed pane: neither side fits, so the bubble stays inside.
        let squeezed = CGSize(width: 400, height: 40)
        let control = CGRect(x: 180, y: 8, width: 26, height: 24)

        let origin = NoteTooltipPlacement.origin(control: control, container: squeezed, tooltip: tooltip)

        XCTAssertGreaterThanOrEqual(origin.y, NoteTooltipPlacement.margin)
    }

    func testABubbleWiderThanThePaneStartsAtTheLeftMargin() {
        let wide = CGSize(width: 460, height: 24)
        let control = CGRect(x: 10, y: 10, width: 26, height: 24)

        let origin = NoteTooltipPlacement.origin(control: control, container: container, tooltip: wide)

        XCTAssertEqual(origin.x, NoteTooltipPlacement.margin, accuracy: 0.001)
    }
}
