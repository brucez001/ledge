import SwiftUI

/// The dock rail: Home, the currently open sessions, and panel controls.
///
/// Favourites live on Home as shortcuts. Once opened, every session appears
/// here with the same menu, close affordance, reordering, and keyboard rules.
struct AppRail: View {
    @ObservedObject var controller: PanelController
    @ObservedObject private var sessionManager: SessionManager
    @State private var isHoveringOptions = false
    @StateObject private var drop = RailDropCoordinator()

    init(controller: PanelController) {
        self.controller = controller
        self.sessionManager = controller.sessionManager
    }

    private var pinSymbol: String {
        controller.isAutoHideEnabled ? "pin.slash" : "pin.fill"
    }

    private var pinHelp: String {
        controller.isAutoHideEnabled
            ? "Keep panel open (currently auto-hides)"
            : "Panel stays open (auto-hide is off)"
    }

    private var entries: [RailEntry] { controller.railEntries }

    private var dragHandle: some View {
        WindowDragHandle()
            .frame(height: 14)
            .overlay {
                Capsule()
                    .fill(Theme.inkTertiary)
                    .frame(width: 18, height: 3)
                    .allowsHitTesting(false)
            }
            .help("Drag to move the panel")
            .accessibilityLabel("Move panel")
    }

    var body: some View {
        VStack(spacing: 4) {
            dragHandle

            RailIconButton(
                systemName: "house",
                label: "Home",
                tooltip: "Search and manage favourites",
                isOn: controller.destination == .home,
                action: controller.goHome
            )

            Divider().padding(.horizontal, 7)

            sessions

            Divider().padding(.horizontal, 7)

            RailIconButton(
                systemName: pinSymbol,
                label: "Auto-hide",
                tooltip: pinHelp,
                isOn: !controller.isAutoHideEnabled,
                action: controller.toggleAutoHide
            )

            optionsMenu
        }
        .frame(width: Theme.Metrics.railWidth)
        .padding(.vertical, 8)
        .background {
            ZStack {
                Theme.rail
                WindowDragHandle()
            }
        }
    }

    private var sessions: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    row(for: entry)
                }

                RailIconButton(
                    systemName: "plus",
                    label: "New session",
                    tooltip: "New session (⌘T)",
                    action: { controller.newTab() }
                )
                .padding(.top, entries.isEmpty ? 0 : 6)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func row(for entry: RailEntry) -> some View {
        if let session = sessionManager.existingSession(for: entry.sessionKind) {
            RailSessionButton(
                controller: controller,
                session: session,
                drop: drop,
                entry: entry,
                isActive: sessionManager.activeSessionID == entry.sessionKind,
                isBlank: entry.tabID.map(controller.blankTabIDs.contains) ?? false,
                canMoveUp: entries.first != entry,
                canMoveDown: entries.last != entry
            )
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button("Add Favourite…") {
                controller.openAddFavourite()
            }
            Button("New Note…") {
                controller.openNewNote()
            }

            Divider()

            Toggle(
                "Auto-hide at screen edge",
                isOn: Binding(
                    get: { controller.isAutoHideEnabled },
                    set: { controller.setAutoHide($0) }
                )
            )

            Divider()

            Button("Dock Left") { controller.setDockSide(.left) }
                .disabled(controller.dockSide == .left)
            Button("Dock Right") { controller.setDockSide(.right) }
                .disabled(controller.dockSide == .right)

            Divider()

            SettingsLink { Text("Settings…") }

            Divider()

            Button("Quit Ledge") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: Theme.Metrics.railItemSize, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius, style: .continuous)
                        .fill(isHoveringOptions ? Theme.controlHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHoveringOptions = $0 }
        .help("More options")
        .accessibilityLabel("More options")
    }
}

/// One open session. Favourite association changes only the Home shortcut
/// toggle; the row itself behaves exactly like every other session.
private struct RailSessionButton: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var session: WebSession
    @ObservedObject var drop: RailDropCoordinator
    let entry: RailEntry
    let isActive: Bool
    let isBlank: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    @State private var isHovering = false
    @State private var pendingFavouriteRemoval: Favourite?

    private var favourite: Favourite? {
        guard let id = session.id.favouriteID else { return nil }
        return controller.favourites.favourite(withID: id)
    }

    private var host: String {
        session.iconHost ?? session.displayHost
    }

    private var tooltip: String {
        if isBlank { return "New session" }
        if let favourite { return favourite.name }
        if !session.pageTitle.isEmpty { return session.pageTitle }
        return host.isEmpty ? "Session" : host
    }

    var body: some View {
        Button {
            controller.openSession(session.id)
        } label: {
            Group {
                if isBlank {
                    Image(systemName: "globe.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                } else {
                    FaviconView(host: host, size: Theme.Metrics.railIconSize)
                        .frame(width: Theme.Metrics.railIconSize, height: Theme.Metrics.railIconSize)
                }
            }
            .frame(width: Theme.Metrics.railItemSize, height: Theme.Metrics.railItemSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(RailButtonBackgroundStyle(isHovering: isHovering, isSelected: isActive))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    controller.closeSession(session.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.ink, Theme.cardHover)
                }
                .buttonStyle(.plain)
                .help("Close session")
                .accessibilityLabel("Close session")
                .offset(x: 3, y: -3)
            }
        }
        .onHover { isHovering = $0 }
        .help(tooltip)
        .accessibilityLabel(
            isBlank
                ? "New session"
                : (isActive ? "Current session: \(tooltip)" : "Session: \(tooltip)")
        )
        .onDrag {
            drop.begin(dragging: entry)
            let payload = switch entry {
            case .favourite(let id): SiteDragPayload.encodeRailFavourite(id)
            case .tab(let id): SiteDragPayload.encodeRailTab(id)
            }
            return NSItemProvider(object: payload as NSString)
        }
        .padding(.vertical, Theme.Metrics.railRowSpacing / 2)
        .overlay(alignment: .top) { insertionLine(isBelow: false) }
        .overlay(alignment: .bottom) { insertionLine(isBelow: true) }
        .onDrop(
            of: [SiteDragPayload.type],
            delegate: RailReorderDropDelegate(
                target: entry,
                controller: controller,
                drop: drop,
                rowHeight: Theme.Metrics.railRowHeight
            )
        )
        .contextMenu {
            RailSessionMenuItems(
                controller: controller,
                session: session,
                entry: entry,
                reordering: RailReordering(
                    entry: entry,
                    controller: controller,
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown
                ),
                confirmFavouriteRemoval: { pendingFavouriteRemoval = $0 }
            )
        }
        .confirmFavouriteRemoval($pendingFavouriteRemoval) {
            controller.removeFavourite($0)
        }
    }

    /// The drop indicator: a short accent bar sitting in the gap between rows,
    /// shown only on the edge the dragged row will actually land against.
    @ViewBuilder
    private func insertionLine(isBelow: Bool) -> some View {
        if drop.showsLine(for: entry, isBelow: isBelow) {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 2)
                .padding(.horizontal, 5)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}

/// Turns a drop on any rail row into an insert-above or insert-below.
private struct RailReorderDropDelegate: DropDelegate {
    let target: RailEntry
    let controller: PanelController
    let drop: RailDropCoordinator
    let rowHeight: CGFloat

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [SiteDragPayload.type])
    }

    func dropEntered(info: DropInfo) {
        updateIndicator(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator(at: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        let target = target
        let drop = drop
        Task { @MainActor in drop.pointerLeft(target) }
    }

    func performDrop(info: DropInfo) -> Bool {
        let isBelow = info.location.y > rowHeight / 2
        let drop = drop
        Task { @MainActor in drop.end() }
        guard let provider = info.itemProviders(for: [SiteDragPayload.type]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let string = reading as? String,
                  let item = SiteDragPayload.decodeItem(string) else { return }
            let dragged: RailEntry = switch item {
            case .site(let id): .favourite(id)
            case .tab(let id): .tab(id)
            }
            Task { @MainActor in
                controller.moveRailEntry(dragged, relativeTo: target, isBelow: isBelow)
            }
        }
        return true
    }

    /// Recomputes the indicator from the pointer's half of this row, using the
    /// same arithmetic `performDrop` applies.
    private func updateIndicator(at location: CGPoint) {
        let isBelow = location.y > rowHeight / 2
        let target = target
        let controller = controller
        let drop = drop
        Task { @MainActor in
            drop.pointerMoved(over: target, isBelow: isBelow, in: controller.railEntries)
        }
    }
}

/// Shared rail control: a fixed hit target with hover and pressed feedback.
private struct RailIconButton: View {
    let systemName: String
    let label: String
    let tooltip: String
    var isOn: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Theme.inkSecondary)
                .frame(width: Theme.Metrics.railItemSize, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(RailButtonBackgroundStyle(isHovering: isHovering, isSelected: isOn))
        .onHover { isHovering = $0 }
        .help(tooltip)
        .accessibilityLabel(label)
    }
}

private struct RailButtonBackgroundStyle: ButtonStyle {
    let isHovering: Bool
    var isSelected: Bool = false

    private var fill: Color {
        if isSelected { return Theme.controlPressed }
        return isHovering ? Theme.controlHover : .clear
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.controlPressed : fill)
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
