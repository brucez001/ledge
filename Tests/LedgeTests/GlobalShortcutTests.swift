import AppKit
import Carbon
import XCTest
@testable import Ledge

final class GlobalShortcutTests: XCTestCase {

    func testEveryShortcutHasADistinctIdentifierAndCombination() {
        let identifiers = GlobalShortcut.allCases.map(\.rawValue)
        XCTAssertEqual(Set(identifiers).count, GlobalShortcut.allCases.count)

        // Two shortcuts sharing a key and modifier mask would mean the second
        // `RegisterEventHotKey` silently loses.
        let combinations = GlobalShortcut.allCases.map { "\($0.keyCode)-\($0.carbonModifiers)" }
        XCTAssertEqual(Set(combinations).count, GlobalShortcut.allCases.count)
    }

    func testEdgeRevealUsesOptionShiftCommandE() {
        let shortcut = GlobalShortcut.toggleEdgeReveal

        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_E))
        XCTAssertEqual(shortcut.carbonModifiers, UInt32(cmdKey | shiftKey | optionKey))
        XCTAssertEqual(shortcut.displayName, "⌥⇧⌘E")
        XCTAssertEqual(shortcut.keyEquivalent, "e")
    }

    func testPanelShortcutIsUnchanged() {
        let shortcut = GlobalShortcut.togglePanel

        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(shortcut.carbonModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(shortcut.displayName, "⇧⌘Space")
        XCTAssertEqual(shortcut.keyEquivalent, " ")
    }

    func testMenuModifierMaskMatchesCarbonModifiers() {
        XCTAssertEqual(GlobalShortcut.togglePanel.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertEqual(GlobalShortcut.toggleEdgeReveal.keyEquivalentModifierMask, [.command, .shift, .option])
    }

    func testKeyEquivalentsAreLowercasedSoModifiersAreNotDoubledUp() {
        // AppKit adds ⇧ itself for an uppercase key equivalent, which would
        // render ⌥⇧⌘E as ⌥⇧⇧⌘E and stop matching the registered hotkey.
        for shortcut in GlobalShortcut.allCases {
            XCTAssertEqual(shortcut.keyEquivalent, shortcut.keyEquivalent.lowercased())
        }
    }
}
