import Combine
import Foundation

/// Owns every open terminal tab.
///
/// Kept as its own small type rather than growing `PanelController`, like
/// `NoteController`. Terminal tabs follow the session rules: they appear in
/// the rail in open order, keep their shells until closed, and come back at
/// the next launch -- splits included -- as rows that start nothing until
/// selected.
@MainActor
final class TerminalController: ObservableObject {
    /// Open terminal tabs in rail order.
    @Published private(set) var tabs: [TerminalTab] = []

    /// Called when one of a tab's shells ends on its own -- `exit`, or a
    /// crash -- never when Ledge ends it.
    var onShellExit: ((TerminalTab, TerminalShell) -> Void)?
    /// Set by the view hosting the terminals, to show one and give it focus
    /// immediately rather than on SwiftUI's next update -- otherwise keys
    /// typed straight after opening a terminal reach whatever had focus.
    var presenter: ((TerminalTab) -> Void)?

    /// Fires when a tab is split, loses a pane, or has a divider moved: the
    /// structural changes worth saving straight away, like opening a tab.
    let arrangementChanged = PassthroughSubject<Void, Never>()

    private var layoutObservers: [UUID: AnyCancellable] = [:]

    /// A new terminal tab with one pane. Its shell starts when the tab is
    /// first shown.
    @discardableResult
    func openNew(in directory: URL? = nil) -> TerminalTab {
        let tab = makeTab(TerminalTab(directory: directory))
        tabs.append(tab)
        return tab
    }

    func tab(for id: UUID) -> TerminalTab? {
        tabs.first { $0.id == id }
    }

    /// Rebuilds the rows a previous launch left in the rail. No shell starts.
    /// Called once, before anything else opens a terminal.
    func restore(_ terminals: [OpenSessionsStore.OpenTerminal]) {
        guard tabs.isEmpty else { return }
        tabs = terminals.map { makeTab(TerminalTab(arrangement: $0.arrangement)) }
    }

    /// Open tabs in rail order, for the next launch. Running shells are read
    /// afresh so each pane reopens where its shell actually is.
    var restorableTerminals: [OpenSessionsStore.OpenTerminal] {
        tabs.map { OpenSessionsStore.OpenTerminal(arrangement: $0.arrangement) }
    }

    /// Ends every shell in the tab and removes it. Callers must already have
    /// confirmed this if a command was running.
    func close(_ id: UUID) {
        guard let tab = tab(for: id) else { return }
        tab.terminateAll()
        layoutObservers[id] = nil
        tabs.removeAll { $0.id == id }
    }

    /// Shows `tab` and gives its focused pane the keyboard now.
    func present(_ tab: TerminalTab) {
        presenter?(tab)
    }

    /// Reorders open tabs after validating a true permutation.
    func setOrder(_ ids: [UUID]) {
        let current = tabs.map(\.id)
        let reordered = ids.compactMap { tab(for: $0) }
        guard Set(reordered.map(\.id)) == Set(current), reordered.count == current.count else { return }
        guard reordered.map(\.id) != current else { return }
        tabs = reordered
    }

    /// Ends every shell, for app termination. The rows stay, so the rail
    /// saved alongside still lists them.
    func terminateAll() {
        for tab in tabs {
            tab.terminateAll()
        }
    }

    private func makeTab(_ tab: TerminalTab) -> TerminalTab {
        tab.onShellExit = { [weak self, weak tab] shell in
            guard let tab else { return }
            self?.onShellExit?(tab, shell)
        }
        layoutObservers[tab.id] = tab.$layout.dropFirst().sink { [weak self] _ in
            self?.arrangementChanged.send()
        }
        return tab
    }
}
