import AppKit
import XCTest
@testable import Ledge

final class TerminalKeypadTests: XCTestCase {
    private func text(
        _ keyCode: UInt16,
        _ characters: String?,
        modifiers: NSEvent.ModifierFlags = .numericPad,
        kittyKeyboard: Bool = false
    ) -> String? {
        TerminalKeypad.text(
            keyCode: keyCode,
            modifiers: modifiers,
            characters: characters,
            kittyKeyboard: kittyKeyboard
        )
    }

    func testDigitsAndOperatorsTypeThemselves() {
        XCTAssertEqual(text(82, "0"), "0")
        XCTAssertEqual(text(87, "5"), "5")
        XCTAssertEqual(text(92, "9"), "9")
        XCTAssertEqual(text(69, "+"), "+")
        XCTAssertEqual(text(81, "="), "=")
    }

    /// Some layouts type a comma from the keypad's decimal key.
    func testTheLayoutDecidesTheCharacter() {
        XCTAssertEqual(text(65, ","), ",")
    }

    func testEnterIsReturn() {
        XCTAssertEqual(text(76, "\u{3}"), "\r")
    }

    func testShiftStillTypes() {
        XCTAssertEqual(text(83, "1", modifiers: [.numericPad, .shift]), "1")
    }

    func testOtherKeysAreLeftToTheTerminal() {
        // Arrow keys carry `.numericPad` too.
        XCTAssertNil(text(126, "\u{F700}", modifiers: [.numericPad, .function]))
        XCTAssertNil(text(71, "\u{F739}")) // Clear
        XCTAssertNil(text(18, "1", modifiers: []))
    }

    func testShortcutsAreLeftToTheTerminal() {
        XCTAssertNil(text(69, "+", modifiers: [.numericPad, .command]))
        XCTAssertNil(text(83, "1", modifiers: [.numericPad, .control]))
        XCTAssertNil(text(83, "¡", modifiers: [.numericPad, .option]))
    }

    func testKittyKeyboardProgramsGetSwiftTermsReports() {
        XCTAssertNil(text(87, "5", kittyKeyboard: true))
        XCTAssertNil(text(76, "\u{3}", kittyKeyboard: true))
    }
}
