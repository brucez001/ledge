import XCTest
@testable import Ledge

final class RailHoverCardPlacementTests: XCTestCase {
    private let container = CGSize(width: 900, height: 600)
    private let card = CGSize(width: 180, height: 40)

    func testOpensLeftwardsWhenTheRailIsDockedRight() {
        let row = CGRect(x: 861, y: 200, width: 34, height: 34)

        let origin = RailHoverCardPlacement.origin(row: row, container: container, card: card, dockSide: .right)

        XCTAssertEqual(origin.x, row.minX - RailHoverCardPlacement.gap - card.width, accuracy: 0.001)
        XCTAssertEqual(origin.y, row.midY - card.height / 2, accuracy: 0.001)
    }

    func testOpensRightwardsWhenTheRailIsDockedLeft() {
        let row = CGRect(x: 5, y: 200, width: 34, height: 34)

        let origin = RailHoverCardPlacement.origin(row: row, container: container, card: card, dockSide: .left)

        XCTAssertEqual(origin.x, row.maxX + RailHoverCardPlacement.gap, accuracy: 0.001)
        XCTAssertEqual(origin.y, row.midY - card.height / 2, accuracy: 0.001)
    }

    func testClampsToTheTopMargin() {
        let row = CGRect(x: 861, y: 0, width: 34, height: 34)

        let origin = RailHoverCardPlacement.origin(row: row, container: container, card: card, dockSide: .right)

        XCTAssertEqual(origin.y, RailHoverCardPlacement.margin, accuracy: 0.001)
    }

    func testClampsToTheBottomMargin() {
        let row = CGRect(x: 861, y: 566, width: 34, height: 34)

        let origin = RailHoverCardPlacement.origin(row: row, container: container, card: card, dockSide: .right)

        XCTAssertEqual(
            origin.y,
            container.height - card.height - RailHoverCardPlacement.margin,
            accuracy: 0.001
        )
    }
}
