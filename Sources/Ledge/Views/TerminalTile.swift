import SwiftUI

/// One open terminal on the Home grid. Clicking selects its tab; the
/// right-click menu matches the sidebar row's. Closing asks first while a
/// command is running, wherever it starts from.
struct TerminalTile: View {
    let controller: PanelController
    @ObservedObject var tab: TerminalTab

    @State private var isHovering = false

    /// A shell's own title is usually `user@host:path`, which a tile this
    /// narrow truncates to the user name, so the tile leads with what is
    /// running, or where.
    private var title: String {
        if let command = tab.runningCommand { return command }
        if let directory = tab.directory { return TerminalPath.name(of: directory) }
        return tab.displayTitle
    }

    private var subtitle: String {
        switch tab.state {
        case .dormant: "Not started"
        case .exited: "Shell ended"
        case .running: tab.directory.map { TerminalPath.abbreviated($0) } ?? ""
        }
    }

    var body: some View {
        Button { controller.openTerminalTab(tab.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                // The same Dock-style dot as a note tile, meaning the shell
                // is running rather than that the tab is open.
                VStack(spacing: 4) {
                    Image(systemName: "apple.terminal")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.inkTertiary)
                    Circle()
                        .fill(Theme.inkSecondary)
                        .frame(width: 4, height: 4)
                        .opacity(tab.isRunning ? 1 : 0)
                }
                .fixedSize()

                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    // A path keeps its end, which is the part that differs.
                    .truncationMode(tab.isRunning ? .head : .tail)
                    .padding(.top, 3)
            }
            .padding(14)
            .frame(width: Theme.Metrics.tileSize, height: Theme.Metrics.tileSize, alignment: .leading)
            .background(
                isHovering ? Theme.cardHover : Theme.card,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
            .tileHoverShadow(isHovering: isHovering)
        }
        .buttonStyle(TilePressStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .contextMenu {
            TerminalMenuItems(controller: controller, tabID: tab.id)
        }
        .help(tab.directory.map { TerminalPath.abbreviated($0) } ?? "Open terminal")
        .accessibilityLabel(tab.isRunning ? "Running terminal: \(title)" : "Terminal: \(title)")
    }
}

/// The dashed "add" tile that opens a new terminal, matching `NewNoteTile`.
struct NewTerminalTile: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Theme.inkSecondary)

                Text("New terminal")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(width: Theme.Metrics.tileSize, height: Theme.Metrics.tileSize)
            .background(
                isHovering ? Theme.cardHover : Theme.card.opacity(0.6),
                in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
            .scaleEffect(isHovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Open a new terminal")
        .help("New terminal (⌥⌘T)")
    }
}
