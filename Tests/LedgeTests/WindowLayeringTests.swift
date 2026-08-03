import AppKit
import XCTest
@testable import Ledge

final class WindowLayeringTests: XCTestCase {

    /// The bug this covers: Settings opened at a normal level, which is below
    /// the panel's floating level, so the window was invisible behind it.
    func testSettingsSitsAbovePanel() {
        XCTAssertGreaterThan(WindowLayering.settings.rawValue, WindowLayering.panel.rawValue)
    }

    func testPanelStaysAtFloatingLevel() {
        XCTAssertEqual(WindowLayering.panel, .floating)
    }
}
