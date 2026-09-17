import XCTest
@testable import Ledge

@MainActor
final class SettingsPresentationTests: XCTestCase {

    /// The bug this covers: SwiftUI presents the `Settings` scene during
    /// launch when it is an app's only scene, so Ledge booted with Settings
    /// sitting open over the panel.
    func testUnrequestedPresentationIsDismissed() {
        XCTAssertTrue(SettingsPresentation.shouldDismissPresentation())
    }

    func testRequestedPresentationIsKept() {
        SettingsPresentation.willOpenAtUserRequest()
        XCTAssertFalse(SettingsPresentation.shouldDismissPresentation())
    }

    /// Guards the menu-bar and rail routes: one request must not leave a
    /// standing permit that admits a later unrequested presentation.
    func testOneRequestAdmitsOnlyOnePresentation() {
        SettingsPresentation.willOpenAtUserRequest()
        XCTAssertFalse(SettingsPresentation.shouldDismissPresentation())
        XCTAssertTrue(SettingsPresentation.shouldDismissPresentation())
    }
}
