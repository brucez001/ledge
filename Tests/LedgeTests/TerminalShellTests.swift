import Darwin
import XCTest
@testable import Ledge

/// Covers terminal tabs and the process questions behind them.
@MainActor
final class TerminalShellTests: XCTestCase {
    // MARK: - Paths

    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    func testDirectoriesReadLikeAPrompt() {
        XCTAssertEqual(TerminalPath.abbreviated(home, home: home), "~")
        XCTAssertEqual(
            TerminalPath.abbreviated(URL(fileURLWithPath: "/Users/someone/src/ledge"), home: home),
            "~/src/ledge"
        )
        XCTAssertEqual(
            TerminalPath.abbreviated(URL(fileURLWithPath: "/Users/someoneelse"), home: home),
            "/Users/someoneelse"
        )
        XCTAssertEqual(TerminalPath.name(of: home, home: home), "~")
        XCTAssertEqual(TerminalPath.name(of: URL(fileURLWithPath: "/Users/someone/src/ledge"), home: home), "ledge")
        XCTAssertEqual(TerminalPath.name(of: URL(fileURLWithPath: "/"), home: home), "/")
    }

    func testAShellsDirectoryReportIsRead() {
        XCTAssertEqual(
            TerminalPath.directory(fromReport: "file://my-mac.local/Users/someone/My%20Project")?.path,
            "/Users/someone/My Project"
        )
        XCTAssertEqual(TerminalPath.directory(fromReport: "/tmp")?.path, "/tmp")
        XCTAssertNil(TerminalPath.directory(fromReport: "https://example.com/x"))
        XCTAssertNil(TerminalPath.directory(fromReport: ""))
        XCTAssertNil(TerminalPath.directory(fromReport: nil))
    }

    // MARK: - Exit status

    func testWaitStatusesBecomeExitStatuses() {
        XCTAssertEqual(LedgeTerminalView.exitStatus(fromWaitStatus: 0), 0)
        XCTAssertEqual(LedgeTerminalView.exitStatus(fromWaitStatus: 3 << 8), 3)
        // Killed by SIGKILL: there is no exit status.
        XCTAssertNil(LedgeTerminalView.exitStatus(fromWaitStatus: SIGKILL))
    }

    /// SwiftTerm silently ignores a palette that is not exactly 16 colours.
    func testBothPalettesCoverEveryANSIColour() {
        XCTAssertEqual(LedgeTerminalView.palette(isDark: false).count, 16)
        XCTAssertEqual(LedgeTerminalView.palette(isDark: true).count, 16)
        XCTAssertNotEqual(LedgeTerminalView.palette(isDark: false), LedgeTerminalView.palette(isDark: true))
    }

    // MARK: - Process inspection

    func testAProcessDirectoryAndNameAreRead() {
        let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath()
        XCTAssertEqual(ShellProcess.currentDirectory(of: getpid())?.resolvingSymlinksInPath().path, expected.path)
        XCTAssertNotNil(ShellProcess.name(of: getpid()))
    }

    func testNoProcessMeansNoAnswer() {
        XCTAssertNil(ShellProcess.currentDirectory(of: 0))
        XCTAssertNil(ShellProcess.name(of: -1))
        XCTAssertNil(ShellProcess.foregroundJob(shellPID: 0))
    }

    // MARK: - Tabs

    func testANewTabStartsNothingAndNamesItsDirectory() {
        let shell = TerminalShell(directory: URL(fileURLWithPath: "/tmp/project", isDirectory: true))

        XCTAssertEqual(shell.state, .dormant)
        XCTAssertNil(shell.view)
        XCTAssertNil(shell.currentCommand())
        XCTAssertEqual(shell.displayTitle, "project")
        XCTAssertTrue(shell.summary.hasSuffix("Starts when opened"))
    }

    func testAShellTitleNamesTheTab() {
        XCTAssertEqual(TerminalShell(title: "  build  ").displayTitle, "build")
        XCTAssertEqual(TerminalShell().displayTitle, "Terminal")
    }

    func testAPaneTitleBarAddsTheDirectoryUnlessTheTitleShowsIt() {
        let projects = URL(fileURLWithPath: "/Users/someone/dev", isDirectory: true)
        func label(_ title: String, _ command: String? = nil, _ directory: URL? = nil) -> [String?] {
            let label = TerminalPaneLabel(
                title: title, runningCommand: command, directory: directory,
                home: home, user: "someone", host: "Someones-Mac.local"
            )
            return [label.title, label.detail]
        }

        XCTAssertEqual(label("", nil, projects), ["~/dev", nil])
        XCTAssertEqual(label("", "vim", projects), ["vim", "~/dev"])
        XCTAssertEqual(label(" someone@someones-mac:~/dev ", nil, projects), ["~/dev", nil])
        XCTAssertEqual(label("someone@build-box:~/dev", nil, projects), ["someone@build-box:~/dev", nil])
        XCTAssertEqual(label("other@Someones-Mac:/srv", nil, projects), ["other@Someones-Mac:/srv", "~/dev"])
        XCTAssertEqual(label("Claude Code", "node", projects), ["Claude Code", "~/dev"])
        XCTAssertEqual(label(""), ["Terminal", nil])
    }

    /// Starts the account's real login shell: the only way to see a
    /// pseudo-terminal, the process table, and reaping working together.
    func testAStartedShellReportsItsDirectoryAndIsCollectedWhenClosed() async throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let shell = TerminalShell(directory: directory)

        shell.start()
        XCTAssertEqual(shell.state, .running)
        let pid = try XCTUnwrap(shell.view?.process.shellPid)

        try await waitUntil {
            shell.refreshStatus()
            return shell.directory?.resolvingSymlinksInPath().path == directory.path
        }

        shell.terminate()
        XCTAssertEqual(shell.state, .dormant)
        XCTAssertNil(shell.view)
        // A zombie still answers `kill(pid, 0)`, so this also proves the
        // shell was waited on.
        try await waitUntil { kill(pid, 0) != 0 }
    }

    func testAShellThatExitsReportsItsStatus() async throws {
        let shell = TerminalShell(directory: FileManager.default.temporaryDirectory)
        var reported: TerminalShell.State?
        shell.onExit = { reported = $0.state }

        shell.start()
        let view = try XCTUnwrap(shell.view)
        view.send(txt: "exit 3\n")

        try await waitUntil { reported != nil }
        XCTAssertEqual(reported, .exited(status: 3))
        XCTAssertEqual(shell.state, .exited(status: 3))
        XCTAssertFalse(shell.isRunning)
    }

    /// What makes ⌘W and quitting ask first.
    func testACommandRunningInFrontOfTheShellIsSeen() async throws {
        let shell = TerminalShell(directory: FileManager.default.temporaryDirectory)
        shell.start()
        defer { shell.terminate() }
        let view = try XCTUnwrap(shell.view)
        XCTAssertNil(shell.currentCommand())

        view.send(txt: "sleep 30\n")

        try await waitUntil { shell.currentCommand() != nil }
        XCTAssertEqual(shell.runningCommand, "sleep")

        view.send(txt: "\u{03}")
        try await waitUntil { shell.currentCommand() == nil }
        XCTAssertNil(shell.runningCommand)
    }

    private func waitUntil(
        timeout: Duration = .seconds(15),
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// Covers the set of open terminal tabs.
@MainActor
final class TerminalControllerTests: XCTestCase {
    private let projects = URL(fileURLWithPath: "/tmp/projects", isDirectory: true)

    func testRestoredRowsStartNoShell() {
        let controller = TerminalController()
        controller.restore([
            .init(arrangement: .pane(directory: projects)),
            .init(arrangement: .pane(directory: nil))
        ])

        XCTAssertEqual(controller.tabs.count, 2)
        XCTAssertTrue(controller.tabs.allSatisfy { $0.state == .dormant && $0.focusedShell.view == nil })
        XCTAssertEqual(controller.restorableTerminals, [
            .init(arrangement: .pane(directory: projects)),
            .init(arrangement: .pane(directory: nil))
        ])
    }

    /// A split terminal comes back split, every pane dormant, in the same
    /// shape and with each pane's directory.
    func testSplitTerminalsAreRestoredWithTheirShape() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        let arrangement = TerminalArrangement.split(
            orientation: .sideBySide,
            fraction: 0.3,
            first: .pane(directory: projects),
            second: .split(
                orientation: .stacked,
                fraction: 0.5,
                first: .pane(directory: home),
                second: .pane(directory: nil)
            )
        )
        let controller = TerminalController()
        controller.restore([.init(arrangement: arrangement)])

        let tab = controller.tabs[0]
        XCTAssertEqual(tab.layout.paneCount, 3)
        XCTAssertTrue(tab.orderedShells.allSatisfy { $0.state == .dormant && $0.view == nil })
        XCTAssertEqual(tab.orderedShells.map(\.directory), [projects, home, nil])
        XCTAssertEqual(controller.restorableTerminals, [.init(arrangement: arrangement)])
    }

    func testRestoringOnlyHappensIntoAnEmptyRail() {
        let controller = TerminalController()
        controller.openNew()
        controller.restore([.init(arrangement: .pane(directory: projects))])

        XCTAssertEqual(controller.tabs.count, 1)
    }

    func testOpeningAddsADormantRowAtTheEnd() {
        let controller = TerminalController()
        let first = controller.openNew()
        let second = controller.openNew(in: projects)

        XCTAssertEqual(controller.tabs.map(\.id), [first.id, second.id])
        XCTAssertEqual(second.directory, projects)
        XCTAssertEqual(second.state, .dormant)
    }

    func testClosingRemovesOnlyThatRow() {
        let controller = TerminalController()
        let first = controller.openNew()
        let second = controller.openNew()

        controller.close(first.id)

        XCTAssertEqual(controller.tabs.map(\.id), [second.id])
        XCTAssertNil(controller.tab(for: first.id))
    }

    func testReorderingAcceptsOnlyAPermutation() {
        let controller = TerminalController()
        let a = controller.openNew()
        let b = controller.openNew()
        let c = controller.openNew()

        controller.setOrder([c.id, a.id])
        XCTAssertEqual(controller.tabs.map(\.id), [a.id, b.id, c.id])

        controller.setOrder([c.id, a.id, b.id])
        XCTAssertEqual(controller.tabs.map(\.id), [c.id, a.id, b.id])
    }

    /// Moving a divider and closing a pane are saved straight away, like
    /// opening a tab, so a crash does not lose them. Focus is not saved.
    func testLayoutChangesAreAnnouncedForSaving() throws {
        let controller = TerminalController()
        controller.restore([.init(arrangement: .split(
            orientation: .sideBySide, fraction: 0.5,
            first: .pane(directory: nil), second: .pane(directory: nil)
        ))])
        let tab = try XCTUnwrap(controller.tabs.first)
        var announcements = 0
        let subscription = controller.arrangementChanged.sink { announcements += 1 }
        defer { subscription.cancel() }

        tab.focusPane(offset: 1)
        XCTAssertEqual(announcements, 0)

        guard case .split(let split) = tab.layout else { return XCTFail("Expected a split") }
        tab.setFraction(0.3, forSplit: split.id)
        XCTAssertEqual(announcements, 1)

        XCTAssertTrue(tab.closePane(tab.focusedShellID))
        XCTAssertEqual(announcements, 2)
    }

    func testDormantRowsAreNeverBusy() {
        let controller = TerminalController()
        let tab = controller.openNew()
        XCTAssertTrue(tab.runningCommands.isEmpty)
    }
}
