import XCTest
@testable import Ledge

/// Covers the split tree behind a terminal tab: its shape, geometry, and
/// moving focus around it.
final class TerminalLayoutTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    /// `a` on the left; `b` above `c` on the right.
    private var threePanes: TerminalLayout {
        TerminalLayout.pane(a)
            .splitting(a, .sideBySide, newPane: b)
            .splitting(b, .stacked, newPane: c)
    }

    // MARK: - Shape

    func testSplittingPutsTheNewPaneRightOfOrBelowTheOld() {
        guard case .split(let split) = TerminalLayout.pane(a).splitting(a, .sideBySide, newPane: b) else {
            return XCTFail("Expected a split")
        }
        XCTAssertEqual(split.orientation, .sideBySide)
        XCTAssertEqual(split.fraction, 0.5)
        XCTAssertEqual(split.first, .pane(a))
        XCTAssertEqual(split.second, .pane(b))
        XCTAssertEqual(threePanes.paneIDs, [a, b, c])
    }

    func testSplittingAMissingPaneChangesNothing() {
        XCTAssertEqual(TerminalLayout.pane(a).splitting(b, .stacked, newPane: c), .pane(a))
    }

    func testRemovingAPaneGivesItsSpaceToItsSibling() {
        XCTAssertEqual(threePanes.removing(b)?.paneIDs, [a, c])
        XCTAssertEqual(threePanes.removing(a)?.paneIDs, [b, c])
        guard case .split(let split) = threePanes.removing(a) else { return XCTFail("Expected a split") }
        XCTAssertEqual(split.orientation, .stacked)
    }

    func testRemovingTheLastPaneLeavesNothing() {
        XCTAssertNil(TerminalLayout.pane(a).removing(a))
        XCTAssertEqual(TerminalLayout.pane(a).removing(b), .pane(a))
    }

    func testDividersStayWithinBounds() throws {
        let layout = threePanes
        guard case .split(let split) = layout else { return XCTFail("Expected a split") }
        guard case .split(let moved) = layout.settingFraction(0.01, forSplit: split.id) else {
            return XCTFail("Expected a split")
        }
        XCTAssertEqual(moved.fraction, TerminalLayout.fractionRange.lowerBound)
        XCTAssertEqual(TerminalLayout.clampedFraction(5), TerminalLayout.fractionRange.upperBound)
        XCTAssertEqual(TerminalLayout.clampedFraction(.nan), 0.5)
    }

    // MARK: - Geometry

    func testGeometryDividesTheSpaceAroundEachDivider() throws {
        let geometry = threePanes.geometry(in: CGRect(x: 0, y: 0, width: 209, height: 109), dividerThickness: 9)

        XCTAssertEqual(geometry.frame(of: a), CGRect(x: 0, y: 0, width: 100, height: 109))
        XCTAssertEqual(geometry.frame(of: b), CGRect(x: 109, y: 0, width: 100, height: 50))
        XCTAssertEqual(geometry.frame(of: c), CGRect(x: 109, y: 59, width: 100, height: 50))
        XCTAssertEqual(geometry.dividers.map(\.frame), [
            CGRect(x: 100, y: 0, width: 9, height: 109),
            CGRect(x: 109, y: 50, width: 100, height: 9)
        ])
    }

    func testDraggingADividerFollowsThePointer() {
        let geometry = TerminalLayout.pane(a)
            .splitting(a, .sideBySide, newPane: b)
            .geometry(in: CGRect(x: 0, y: 0, width: 209, height: 100), dividerThickness: 9)
        let divider = geometry.dividers[0]

        XCTAssertEqual(divider.fraction(at: CGPoint(x: 104.5, y: 40)), 0.5, accuracy: 0.001)
        XCTAssertEqual(divider.fraction(at: CGPoint(x: 64.5, y: 40)), 0.3, accuracy: 0.001)
        XCTAssertEqual(divider.fraction(at: CGPoint(x: -50, y: 40)), TerminalLayout.fractionRange.lowerBound)
    }

    // MARK: - Focus

    func testArrowsMoveToTheAdjacentPane() {
        let geometry = threePanes.geometry(in: CGRect(x: 0, y: 0, width: 1000, height: 1000), dividerThickness: 0)

        XCTAssertEqual(geometry.neighbour(of: a, toward: .right), b)
        XCTAssertNil(geometry.neighbour(of: a, toward: .left))
        XCTAssertNil(geometry.neighbour(of: a, toward: .up))
        XCTAssertEqual(geometry.neighbour(of: b, toward: .down), c)
        XCTAssertEqual(geometry.neighbour(of: c, toward: .up), b)
        XCTAssertEqual(geometry.neighbour(of: c, toward: .left), a)
        XCTAssertNil(geometry.neighbour(of: c, toward: .right))
    }

    func testCyclingWrapsRound() {
        XCTAssertEqual(threePanes.pane(from: a, movedBy: 1), b)
        XCTAssertEqual(threePanes.pane(from: c, movedBy: 1), a)
        XCTAssertEqual(threePanes.pane(from: a, movedBy: -1), c)
        XCTAssertNil(threePanes.pane(from: UUID(), movedBy: 1))
    }

    // MARK: - Saving

    func testArrangementsRoundTripThroughJSON() throws {
        let arrangement = TerminalArrangement.split(
            orientation: .stacked,
            fraction: 0.25,
            first: .pane(directory: URL(fileURLWithPath: "/tmp/a", isDirectory: true)),
            second: .pane(directory: nil)
        )
        let data = try JSONEncoder().encode(arrangement)
        XCTAssertEqual(try JSONDecoder().decode(TerminalArrangement.self, from: data), arrangement)
    }
}

/// Covers a terminal tab's panes, without starting a shell.
@MainActor
final class TerminalTabTests: XCTestCase {
    func testANewTabHasOneDormantPane() {
        let tab = TerminalTab(directory: URL(fileURLWithPath: "/tmp/project", isDirectory: true))
        XCTAssertFalse(tab.isSplit)
        XCTAssertEqual(tab.state, .dormant)
        XCTAssertEqual(tab.displayTitle, "project")
        XCTAssertFalse(tab.closePane(tab.focusedShellID), "The last pane closes with its tab")
    }

    func testFocusMovesBetweenRestoredPanes() {
        let tab = TerminalTab(arrangement: .split(
            orientation: .sideBySide, fraction: 0.5,
            first: .pane(directory: nil), second: .pane(directory: nil)
        ))
        let ids = tab.layout.paneIDs
        XCTAssertEqual(tab.focusedShellID, ids[0])

        XCTAssertTrue(tab.focusPane(toward: .right))
        XCTAssertEqual(tab.focusedShellID, ids[1])
        XCTAssertFalse(tab.focusPane(toward: .right))

        tab.focusPane(offset: 1)
        XCTAssertEqual(tab.focusedShellID, ids[0])
        XCTAssertTrue(tab.summary.hasSuffix("2 panes"))
    }

    func testClosingTheFocusedPaneFocusesTheOneThatTakesItsPlace() {
        let tab = TerminalTab(arrangement: .split(
            orientation: .stacked, fraction: 0.5,
            first: .pane(directory: nil),
            second: .split(orientation: .sideBySide, fraction: 0.5, first: .pane(directory: nil), second: .pane(directory: nil))
        ))
        let ids = tab.layout.paneIDs
        tab.focus(ids[1])

        XCTAssertTrue(tab.closePane(ids[1]))
        XCTAssertEqual(tab.layout.paneIDs, [ids[0], ids[2]])
        XCTAssertEqual(tab.focusedShellID, ids[2])
        XCTAssertNil(tab.shell(for: ids[1]))
    }

    /// Splits a real login shell, so the new pane starts beside it in the
    /// same directory.
    func testSplittingStartsANewShellInTheFocusedPanesDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let tab = TerminalTab(directory: directory)
        tab.startDormantShells(fontSize: 12)
        defer { tab.terminateAll() }
        let original = tab.focusedShellID

        let added = tab.split(.stacked, fontSize: 12)

        XCTAssertEqual(tab.layout.paneIDs, [original, added.id])
        XCTAssertEqual(tab.focusedShellID, added.id)
        XCTAssertEqual(added.state, .running)
        XCTAssertEqual(added.directory?.resolvingSymlinksInPath().path, directory.path)
        guard case .split(.stacked, _, .pane, .pane) = tab.arrangement else {
            return XCTFail("Expected two stacked panes")
        }
    }
}

final class TerminalClosingTests: XCTestCase {
    private let tab = UUID()

    func testTheWordingNamesWhatIsClosingAndWhatItEnds() {
        let pane = TerminalCloseRequest(tabID: tab, paneID: UUID(), commands: ["vim"])
        XCTAssertEqual(TerminalClosing.title(for: pane), "Close this pane?")
        XCTAssertEqual(TerminalClosing.buttonTitle(for: pane), "Close Pane")
        XCTAssertEqual(TerminalClosing.message(for: pane), "\u{201C}vim\u{201D} is still running. Closing the pane ends it.")

        let whole = TerminalCloseRequest(tabID: tab, paneID: nil, commands: ["vim", "npm", "top"])
        XCTAssertEqual(TerminalClosing.title(for: whole), "Close this terminal?")
        XCTAssertEqual(
            TerminalClosing.message(for: whole),
            "\u{201C}vim\u{201D}, \u{201C}npm\u{201D} and \u{201C}top\u{201D} are still running. Closing the terminal ends them."
        )
    }

    func testListsJoinLikeProse() {
        XCTAssertEqual(TerminalClosing.list([]), "")
        XCTAssertEqual(TerminalClosing.list(["a"]), "a")
        XCTAssertEqual(TerminalClosing.list(["a", "b"]), "a and b")
    }
}
