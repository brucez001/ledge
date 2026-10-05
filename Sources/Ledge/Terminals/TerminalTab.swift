import Combine
import CoreGraphics
import Foundation

/// One terminal row in the rail: one or more shells, arranged in splits.
///
/// Everything the rail, Home, and ⌘W need to know about "the terminal" comes
/// from the focused pane, except whether anything is running and which
/// commands are, which cover every pane because closing the tab ends them all.
@MainActor
final class TerminalTab: ObservableObject, Identifiable {
    nonisolated let id: UUID
    @Published private(set) var layout: TerminalLayout
    @Published private(set) var focusedShellID: UUID
    private(set) var shells: [UUID: TerminalShell] = [:]

    /// Called when one of the tab's shells ends on its own.
    var onShellExit: ((TerminalShell) -> Void)?

    private var shellObservers: [UUID: AnyCancellable] = [:]

    init(directory: URL? = nil) {
        let shell = TerminalShell(directory: directory)
        id = UUID()
        layout = .pane(shell.id)
        focusedShellID = shell.id
        adopt(shell)
    }

    /// A tab rebuilt from a previous launch. No shell starts.
    init(arrangement: TerminalArrangement) {
        var made: [TerminalShell] = []
        let layout = Self.layout(for: arrangement, making: &made)
        id = UUID()
        self.layout = layout
        focusedShellID = layout.paneIDs[0]
        for shell in made {
            adopt(shell)
        }
    }

    // MARK: - Panes

    /// Every shell in reading order.
    var orderedShells: [TerminalShell] {
        layout.paneIDs.compactMap { shells[$0] }
    }

    var focusedShell: TerminalShell {
        shells[focusedShellID] ?? orderedShells[0]
    }

    func shell(for id: UUID) -> TerminalShell? {
        shells[id]
    }

    var isSplit: Bool { layout.paneCount > 1 }

    // MARK: - What the rail and Home show

    var state: TerminalShell.State { focusedShell.state }
    var directory: URL? { focusedShell.directory }
    var runningCommand: String? { focusedShell.runningCommand }
    var displayTitle: String { focusedShell.displayTitle }

    /// Whether any pane's shell is running.
    var isRunning: Bool {
        orderedShells.contains(where: \.isRunning)
    }

    var summary: String {
        let focused = focusedShell.summary
        guard isSplit else { return focused }
        let panes = "\(layout.paneCount) panes"
        return focused.isEmpty ? panes : "\(focused) · \(panes)"
    }

    /// Commands running in any pane, read afresh, in reading order.
    var runningCommands: [String] {
        orderedShells.compactMap { $0.currentCommand() }
    }

    // MARK: - Lifecycle

    /// Starts every pane that has never had a shell.
    func startDormantShells(fontSize: Double) {
        for shell in orderedShells where shell.state == .dormant {
            shell.start(fontSize: fontSize)
        }
    }

    /// Divides the focused pane, starting a new shell in its directory and
    /// focusing it.
    @discardableResult
    func split(_ orientation: TerminalSplitOrientation, fontSize: Double) -> TerminalShell {
        let source = focusedShell
        source.refreshStatus()
        let shell = TerminalShell(directory: source.directory)
        adopt(shell)
        layout = layout.splitting(source.id, orientation, newPane: shell.id)
        focusedShellID = shell.id
        shell.start(fontSize: fontSize)
        return shell
    }

    /// Ends one pane's shell and gives its space to its neighbour. Returns
    /// `false`, changing nothing, for the last pane: closing that closes the
    /// tab, which is the caller's to do.
    @discardableResult
    func closePane(_ id: UUID) -> Bool {
        guard isSplit, let shell = shells[id], let remaining = layout.removing(id) else { return false }
        if focusedShellID == id, let successor = RailSelection.successor(after: id, in: layout.paneIDs) {
            focusedShellID = successor
        }
        shell.terminate()
        shellObservers[id] = nil
        shells[id] = nil
        layout = remaining
        return true
    }

    func focus(_ id: UUID) {
        guard shells[id] != nil, id != focusedShellID else { return }
        focusedShellID = id
    }

    /// Moves focus to the pane beside the focused one. Returns whether there
    /// was one.
    @discardableResult
    func focusPane(toward direction: TerminalPaneDirection) -> Bool {
        // Neighbours depend on the shape of the splits, not the size of the
        // pane area, so any square will do.
        let geometry = layout.geometry(in: CGRect(x: 0, y: 0, width: 1000, height: 1000), dividerThickness: 0)
        guard let id = geometry.neighbour(of: focusedShellID, toward: direction) else { return false }
        focus(id)
        return true
    }

    /// Moves focus `offset` panes along in reading order, wrapping round.
    func focusPane(offset: Int) {
        guard let id = layout.pane(from: focusedShellID, movedBy: offset) else { return }
        focus(id)
    }

    func setFraction(_ fraction: Double, forSplit id: UUID) {
        let updated = layout.settingFraction(fraction, forSplit: id)
        guard updated != layout else { return }
        layout = updated
    }

    /// Ends every shell. The panes stay, dormant.
    func terminateAll() {
        for shell in orderedShells {
            shell.terminate()
        }
    }

    // MARK: - Saving

    /// The tab's shape and directories, read afresh from the shells.
    var arrangement: TerminalArrangement {
        arrangement(of: layout)
    }

    private func arrangement(of layout: TerminalLayout) -> TerminalArrangement {
        switch layout {
        case .pane(let id):
            let shell = shells[id]
            shell?.refreshStatus()
            return .pane(directory: shell?.directory)
        case .split(let split):
            return .split(
                orientation: split.orientation,
                fraction: split.fraction,
                first: arrangement(of: split.first),
                second: arrangement(of: split.second)
            )
        }
    }

    private static func layout(
        for arrangement: TerminalArrangement,
        making shells: inout [TerminalShell]
    ) -> TerminalLayout {
        switch arrangement {
        case .pane(let directory):
            let shell = TerminalShell(directory: directory)
            shells.append(shell)
            return .pane(shell.id)
        case .split(let orientation, let fraction, let first, let second):
            return .split(TerminalSplit(
                id: UUID(),
                orientation: orientation,
                fraction: TerminalLayout.clampedFraction(fraction),
                first: layout(for: first, making: &shells),
                second: layout(for: second, making: &shells)
            ))
        }
    }

    private func adopt(_ shell: TerminalShell) {
        shells[shell.id] = shell
        shell.onExit = { [weak self] shell in self?.onShellExit?(shell) }
        shell.onFocus = { [weak self] shell in self?.focus(shell.id) }
        shellObservers[shell.id] = shell.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
