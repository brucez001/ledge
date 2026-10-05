import SwiftUI

/// Wording for ending a terminal, or one of its panes, while a command is
/// still running in it.
enum TerminalClosing {
    static func title(for request: TerminalCloseRequest) -> String {
        request.paneID == nil ? "Close this terminal?" : "Close this pane?"
    }

    static func buttonTitle(for request: TerminalCloseRequest) -> String {
        request.paneID == nil ? "Close Terminal" : "Close Pane"
    }

    static func message(for request: TerminalCloseRequest) -> String {
        let target = request.paneID == nil ? "the terminal" : "the pane"
        let commands = request.commands
        guard commands.count > 1 else {
            return "\(quoted(commands.first ?? "A command")) is still running. Closing \(target) ends it."
        }
        return "\(list(commands.map(quoted))) are still running. Closing \(target) ends them."
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    private static func quoted(_ text: String) -> String {
        "\u{201C}\(text)\u{201D}"
    }
}

extension View {
    /// Asks before a close that would end a running command.
    func confirmTerminalClose(
        _ request: Binding<TerminalCloseRequest?>,
        close: @escaping (TerminalCloseRequest) -> Void
    ) -> some View {
        confirmationDialog(
            request.wrappedValue.map(TerminalClosing.title(for:)) ?? "",
            isPresented: Binding(
                get: { request.wrappedValue != nil },
                set: { if !$0 { request.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: request.wrappedValue
        ) { pending in
            Button(TerminalClosing.buttonTitle(for: pending), role: .destructive) { close(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(TerminalClosing.message(for: pending))
        }
    }
}

/// A terminal's menu, in the rail and on Home. Only the rail can reorder it.
struct TerminalMenuItems: View {
    let controller: PanelController
    let tabID: UUID
    var reordering: RailReordering?

    var body: some View {
        Button("Open") { controller.openTerminalTab(tabID) }
        Button("Duplicate") { controller.duplicateTerminal(tabID) }
        Button("Split Right") { controller.splitTerminal(.sideBySide, tabID: tabID) }
        Button("Split Down") { controller.splitTerminal(.stacked, tabID: tabID) }

        if let reordering {
            RailMoveItems(reordering: reordering)
        }

        Divider()

        Button("Close Terminal") { controller.requestCloseTerminal(tabID) }
    }
}
