import AppKit
import Combine
import SwiftTerm

/// One shell running in a pseudo-terminal, drawn by SwiftTerm: a single pane
/// of a terminal tab.
///
/// Like a web session, a shell keeps running -- and so does whatever it is
/// running -- while the panel hides or another row is selected, until the
/// user closes it. A restored pane is `dormant`: it remembers a directory and
/// starts no shell until its tab is selected, so launching Ledge at login
/// never starts a process.
@MainActor
final class TerminalShell: ObservableObject, Identifiable {
    enum State: Equatable {
        /// No shell has been started yet.
        case dormant
        case running
        /// The shell ended on its own. `status` is its exit status, if known.
        case exited(status: Int32?)
    }

    nonisolated let id: UUID
    @Published private(set) var state: State = .dormant
    /// What the shell asked the terminal to call itself, if anything.
    @Published private(set) var title: String
    /// The shell's working directory, as last read.
    @Published private(set) var directory: URL?
    /// The command running in front of the shell, or `nil` at the prompt.
    @Published private(set) var runningCommand: String?

    /// The terminal view, created the first time the shell starts. It is
    /// replaced, never reused, when a finished shell is restarted, so a new
    /// shell does not inherit modes the old one left behind.
    private(set) var view: LedgeTerminalView?
    /// Called when the shell ends on its own, never when Ledge ends it.
    var onExit: ((TerminalShell) -> Void)?
    /// Called when the user clicks into this shell's terminal.
    var onFocus: ((TerminalShell) -> Void)?

    private var statusRefresh: Task<Void, Never>?

    init(title: String = "", directory: URL? = nil) {
        self.id = UUID()
        self.title = title
        self.directory = directory
    }

    var isRunning: Bool { state == .running }

    /// The row's name: the shell's own title, else the running command, else
    /// the directory.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let runningCommand { return runningCommand }
        if let directory { return TerminalPath.name(of: directory) }
        return "Terminal"
    }

    /// The name on a split pane's title bar, which has room for the whole
    /// directory rather than only its last component.
    var paneLabel: TerminalPaneLabel {
        TerminalPaneLabel(title: title, runningCommand: runningCommand, directory: directory)
    }

    /// Where the shell is, and what it is doing, for the rail's hover card.
    var summary: String {
        var parts: [String] = []
        if let directory { parts.append(TerminalPath.abbreviated(directory)) }
        switch state {
        case .dormant:
            parts.append("Starts when opened")
        case .running:
            if let runningCommand, runningCommand != displayTitle {
                parts.append("Running \(runningCommand)")
            }
        case .exited:
            parts.append("Shell ended")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Lifecycle

    /// Starts the shell unless one is already running: for a dormant pane when
    /// its tab is first shown, and for a finished one when the user restarts it.
    func start(fontSize: Double = TerminalFontSize.standard) {
        guard state != .running else { return }
        if let view {
            view.removeFromSuperview()
        }
        let view = LedgeTerminalView.make(fontSize: fontSize)
        view.processDelegate = self
        view.onOutput = { [weak self] in self?.scheduleStatusRefresh() }
        view.onShellExit = { [weak self] status in self?.shellDidExit(status: status) }
        view.onClick = { [weak self] in
            guard let self else { return }
            self.onFocus?(self)
        }
        self.view = view

        let launch = ShellLaunch.current(directory: directory)
        view.startProcess(
            executable: launch.executable,
            environment: launch.environment,
            execName: launch.execName,
            currentDirectory: launch.directory
        )
        directory = URL(fileURLWithPath: launch.directory, isDirectory: true)
        runningCommand = nil
        state = view.process.running ? .running : .exited(status: nil)
    }

    /// Ends the shell and everything running in it. Callers must already have
    /// confirmed this with the user if a command was running.
    func terminate() {
        statusRefresh?.cancel()
        statusRefresh = nil
        guard let view else { return }
        if state == .running {
            let pid = view.process.shellPid
            let job = ShellProcess.foregroundJob(shellPID: pid)
            view.onShellExit = nil
            // SwiftTerm stops watching the shell here and sends only SIGTERM,
            // which an interactive shell ignores. The hang-up that follows is
            // what ends it, and it passes SIGHUP on to its jobs; the job in
            // front is told directly as well. The shell is still unwaited, so
            // its pid cannot have been reused by then.
            view.terminate()
            if let job {
                killpg(job, SIGHUP)
            }
            ShellReaper.hangUp(pid)
        }
        view.removeFromSuperview()
        self.view = nil
        state = .dormant
    }

    /// The command closing would end, read afresh rather than from the last
    /// output-driven refresh.
    func currentCommand() -> String? {
        refreshStatus()
        return runningCommand
    }

    // MARK: - Status

    /// Re-reads the working directory and the foreground command. Output is
    /// what follows a `cd`, a command starting, or one finishing, so this is
    /// driven by output rather than a timer.
    func refreshStatus() {
        guard state == .running, let process = view?.process else {
            if runningCommand != nil { runningCommand = nil }
            return
        }
        if let current = ShellProcess.currentDirectory(of: process.shellPid), current != directory {
            directory = current
        }
        let job = ShellProcess.foregroundJob(shellPID: process.shellPid)
        let command = job.flatMap(ShellProcess.name(of:))
        if command != runningCommand {
            runningCommand = command
        }
    }

    private func scheduleStatusRefresh() {
        guard statusRefresh == nil else { return }
        statusRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.statusRefresh = nil
            self.refreshStatus()
        }
    }

    private func shellDidExit(status: Int32?) {
        statusRefresh?.cancel()
        statusRefresh = nil
        runningCommand = nil
        state = .exited(status: status)
        onExit?(self)
    }
}

extension TerminalShell: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard title != self.title else { return }
        self.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let url = TerminalPath.directory(fromReport: directory), url != self.directory else { return }
        self.directory = url
    }

    /// Exit is reported through `LedgeTerminalView.onShellExit` instead, so
    /// it can be detached before Ledge ends a shell itself.
    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}

/// Directory formatting shared by the rail and the restore path.
enum TerminalPath {
    /// A directory as a shell prompt shows it: `~/Projects`, or `~` for home.
    static func abbreviated(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    /// The last path component, or `~` for home.
    static func name(of url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let abbreviated = abbreviated(url, home: home)
        if abbreviated == "~" || abbreviated == "/" { return abbreviated }
        return url.standardizedFileURL.lastPathComponent
    }

    /// Reads the directory a shell reports with OSC 7, which is a `file://`
    /// URL whose host names the machine. A bare path is accepted too.
    static func directory(fromReport report: String?) -> URL? {
        guard let report, !report.isEmpty else { return nil }
        if report.hasPrefix("/") {
            return URL(fileURLWithPath: report, isDirectory: true)
        }
        guard let url = URL(string: report), url.isFileURL, !url.path.isEmpty else { return nil }
        return URL(fileURLWithPath: url.path, isDirectory: true)
    }
}

/// What a split pane's title bar says: the shell's own title, else what is
/// running, else where it is -- followed by the directory whenever the title
/// does not already show it, so panes running the same thing in different
/// places still read differently.
struct TerminalPaneLabel: Equatable {
    let title: String
    let detail: String?

    init(
        title shellTitle: String,
        runningCommand: String?,
        directory: URL?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        user: String = NSUserName(),
        host: String = TerminalPaneLabel.localHost
    ) {
        let path = directory.map { TerminalPath.abbreviated($0, home: home) }
        let trimmed = Self.removingLocalPrefix(
            from: shellTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            user: user,
            host: host
        )
        let title = trimmed.isEmpty ? runningCommand ?? path ?? "Terminal" : trimmed
        self.title = title
        detail = path.flatMap { title.contains($0) ? nil : $0 }
    }

    /// zsh and bash setups commonly title a terminal `user@host:directory`.
    /// Every pane on this Mac shares the `user@host:`, so it is dropped; a
    /// title naming another user or machine, as over ssh, is kept whole.
    static func removingLocalPrefix(from title: String, user: String, host: String) -> String {
        guard title.hasPrefix(user + "@"), let colon = title.firstIndex(of: ":") else { return title }
        let titleHost = title[title.index(title.startIndex, offsetBy: user.count + 1)..<colon]
        guard Self.shortName(of: titleHost) == Self.shortName(of: host) else { return title }
        let rest = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? title : rest
    }

    /// The host name up to its first dot, which is what `%m` and `\h` show.
    private static func shortName(of host: some StringProtocol) -> String {
        String(host.prefix { $0 != "." }).lowercased()
    }

    /// This Mac's name as `gethostname` reports it, which unlike
    /// `ProcessInfo.hostName` never waits on a network lookup.
    static let localHost: String = {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&buffer, buffer.count - 1) == 0 else { return "" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }()
}
