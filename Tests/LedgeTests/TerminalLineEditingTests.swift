import AppKit
import XCTest
@testable import Ledge

final class TerminalLineEditingTests: XCTestCase {
    private let left: UInt16 = 123
    private let right: UInt16 = 124
    private let delete: UInt16 = 51
    private let forwardDelete: UInt16 = 117

    /// Arrow keys and forward delete arrive with these as well.
    private let arrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]

    private func bytes(
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags,
        kittyKeyboard: Bool = false,
        alternateScreen: Bool = false
    ) -> [UInt8]? {
        TerminalLineEditing.bytes(
            keyCode: keyCode,
            modifiers: modifiers,
            kittyKeyboard: kittyKeyboard,
            alternateScreen: alternateScreen
        )
    }

    func testOptionMovesAndDeletesByWord() {
        XCTAssertEqual(bytes(left, arrowFlags.union(.option)), [0x1B, 0x62])
        XCTAssertEqual(bytes(right, arrowFlags.union(.option)), [0x1B, 0x66])
        XCTAssertEqual(bytes(delete, .option), [0x1B, 0x7F])
        XCTAssertEqual(bytes(forwardDelete, [.function, .option]), [0x1B, 0x64])
    }

    func testCommandMovesAndDeletesToTheLineEnds() {
        XCTAssertEqual(bytes(left, arrowFlags.union(.command)), [0x01])
        XCTAssertEqual(bytes(right, arrowFlags.union(.command)), [0x05])
        XCTAssertEqual(bytes(delete, .command), [0x15])
        XCTAssertEqual(bytes(forwardDelete, [.function, .command]), [0x0B])
    }

    func testCapsLockDoesNotMatter() {
        XCTAssertEqual(bytes(delete, [.option, .capsLock]), [0x1B, 0x7F])
    }

    func testUnmodifiedKeysAreLeftToTheTerminal() {
        XCTAssertNil(bytes(left, arrowFlags))
        XCTAssertNil(bytes(delete, []))
    }

    /// ⌥⌘arrow moves between panes, and Shift extends a selection.
    func testOtherCombinationsAreLeftToTheTerminal() {
        XCTAssertNil(bytes(left, arrowFlags.union([.option, .command])))
        XCTAssertNil(bytes(left, arrowFlags.union([.option, .shift])))
        XCTAssertNil(bytes(right, arrowFlags.union([.command, .shift])))
        XCTAssertNil(bytes(left, arrowFlags.union(.control)))
        XCTAssertNil(bytes(delete, [.option, .control]))
    }

    func testOtherKeysAreLeftToTheTerminal() {
        XCTAssertNil(bytes(126, arrowFlags.union(.option))) // up
        XCTAssertNil(bytes(125, arrowFlags.union(.command))) // down
        XCTAssertNil(bytes(11, .option)) // B
    }

    func testFullScreenProgramsGetSwiftTermsKeys() {
        XCTAssertNil(bytes(left, arrowFlags.union(.command), alternateScreen: true))
        XCTAssertNil(bytes(delete, .option, alternateScreen: true))
    }

    func testKittyKeyboardProgramsGetSwiftTermsReports() {
        XCTAssertNil(bytes(left, arrowFlags.union(.option), kittyKeyboard: true))
        XCTAssertNil(bytes(delete, .command, kittyKeyboard: true))
    }
}
