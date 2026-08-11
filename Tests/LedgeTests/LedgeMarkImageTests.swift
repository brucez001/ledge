import AppKit
import XCTest
@testable import Ledge

final class LedgeMarkImageTests: XCTestCase {
    func testMarkIsAStatusItemSizedTemplateImage() {
        let image = LedgeMarkImage.make(dockSide: .left)

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.accessibilityDescription, "Ledge")
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testBothDockSidesRenderTheMark() {
        let left = LedgeMarkImage.make(dockSide: .left)
        let right = LedgeMarkImage.make(dockSide: .right)

        let leftRepresentation = left.tiffRepresentation
        let rightRepresentation = right.tiffRepresentation

        XCTAssertNotNil(leftRepresentation)
        XCTAssertNotNil(rightRepresentation)
        XCTAssertNotEqual(leftRepresentation, rightRepresentation)
    }
}
