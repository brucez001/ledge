import SwiftUI

/// The dock rail: Home, the currently open sessions, and panel controls.
///
/// Favourites live on Home as shortcuts. Once opened, every session appears
/// here with the same menu, close affordance, reordering, and keyboard rules.
struct AppRail: View {
    @ObservedObject var controller: PanelController
    @ObservedObject private var sessionManager: SessionManager
    /// Observed directly, not read through `controller`: opening, closing,
    /// or reordering a note tab only publishes on `NoteController`, and
    /// SwiftUI skips re-evaluating this view's body while its own stored
    /// values are unchanged. Without this the rail keeps a row for a note
    /// tab that has already been closed.
    @ObservedObject private var noteController: NoteController
    /// Only needed for the row insert/remove animation, so the rail
    /// follows the same speed setting as the rest of the panel.
    @ObservedObject private var preferences: Preferences
    @State private var isHoveringOptions = false
    @StateObject private var drop = RailDropCoordinator()

    init(controller: PanelController) {
        self.controller = controller
        self.sessionManager = controller.sessionManager
        self.noteController = controller.noteController
        self.preferences = controller.preferences
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
    private var sessionEntries: [RailEntry] { entries.filter { $0.noteID == nil } }
    private var noteEntries: [RailEntry] { entries.filter { $0.noteID != nil } }

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
                VStack(spacing: 0) {
                    ForEach(sessionEntries) { entry in
                        row(for: entry)
                    }

                    RailIconButton(
                        systemName: "plus",
                        label: "New session",
                        tooltip: "New session (⌘T)",
                        action: { controller.newTab() }
                    )
                    .padding(.top, sessionEntries.isEmpty ? 0 : 6)
                }
                .animation(preferences.animationSpeed.contentAnimation, value: sessionEntries)

                if !noteEntries.isEmpty {
                    Divider()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)

                    VStack(spacing: 0) {
                        ForEach(noteEntries) { entry in
                            row(for: entry)
                        }
                    }
                    .animation(preferences.animationSpeed.contentAnimation, value: noteEntries)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func row(for entry: RailEntry) -> some View {
        switch entry {
        case .note(let id):
            if let tab = noteController.tab(for: id) {
                RailNoteButton(
                    controller: controller,
                    tab: tab,
                    drop: drop,
                    entry: entry,
                    isActive: controller.activeNoteID == id,
                    canMoveUp: noteEntries.first != entry,
                    canMoveDown: noteEntries.last != entry
                )
            }
        case .favourite, .tab:
            if let kind = entry.sessionKind,
               let session = sessionManager.existingSession(for: kind) {
                RailSessionButton(
                    controller: controller,
                    session: session,
                    drop: drop,
                    entry: entry,
                    isActive: sessionManager.activeSessionID == kind,
                    isBlank: entry.tabID.map(controller.blankTabIDs.contains) ?? false,
                    canMoveUp: sessionEntries.first != entry,
                    canMoveDown: sessionEntries.last != entry
                )
            }
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

            // Only meaningful while a note is open, and the menu is where
            // ⇧⌘P can be discovered without hovering the header. The item
            // observes the tab itself, so its label follows the mode
            // instead of going stale after a ⇧⌘P from the keyboard.
            if let id = controller.activeNoteID, let tab = noteController.tab(for: id) {
                NotePreviewMenuItem(tab: tab)
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

/// The rail menu's Markdown mode item, split out so it can observe the note
/// tab and keep its label in step with ⇧⌘P.
private struct NotePreviewMenuItem: View {
    @ObservedObject var tab: NoteTab

    var body: some View {
        Button(tab.isPreviewing ? "Edit Markdown" : "Preview Markdown") {
            tab.togglePreview()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
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
            case .note(let id): SiteDragPayload.encodeRailNote(id)
            }
            return NSItemProvider(object: payload as NSString)
        }
        .padding(.vertical, Theme.Metrics.railRowSpacing / 2)
        .overlay(alignment: .top) {
            RailInsertionLine(drop: drop, entry: entry, isBelow: false)
        }
        .overlay(alignment: .bottom) {
            RailInsertionLine(drop: drop, entry: entry, isBelow: true)
        }
        .onDrop(
            of: [SiteDragPayload.type],
            delegate: RailReorderDropDelegate(
                target: entry,
                controller: controller,
                drop: drop,
                rowHeight: Theme.Metrics.railRowHeight
            )
        )
        // Applied last, so it sits *outside* `.onDrag` above: a draggable
        // wrapper swallows mouse-down for the controls inside it, which is
        // what stopped this ✕ from ever firing.
        .overlay(alignment: .topTrailing) {
            if isHovering {
                RailCloseButton(
                    tooltip: "Close session",
                    label: "Close session",
                    keepVisible: { isHovering = true },
                    action: { controller.closeSession(session.id) }
                )
            }
        }
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

}

/// One open note tab. Behaves exactly like a session row: clicking
/// selects it, the hover ✕ closes it (without deleting the file), and the
/// context menu offers the same open / move / close actions, plus the
/// note-only delete (a session has no file to remove).
private struct RailNoteButton: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var tab: NoteTab
    @ObservedObject var drop: RailDropCoordinator
    let entry: RailEntry
    let isActive: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    @State private var isHovering = false
    @State private var isConfirmingDelete = false

    /// The Home tile's one-line peek, computed against the live editor
    /// buffer so the card keeps up with typing rather than the last autosave.
    private var preview: String {
        var live = tab.note
        live.body = tab.body
        return live.preview
    }

    var body: some View {
        Button {
            controller.openNoteTab(tab.note.id)
        } label: {
            Image(systemName: "note.text")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Theme.inkSecondary)
                .frame(width: Theme.Metrics.railItemSize, height: Theme.Metrics.railItemSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(RailButtonBackgroundStyle(isHovering: isHovering, isSelected: isActive))
        .onHover { isHovering = $0 }
        // Every note shares one glyph, so the row needs a name on hover.
        // Ledge's own card rather than `.help()`: see `RailHoverCard.swift`.
        .railHoverCard(id: tab.note.id, title: tab.displayTitle, subtitle: preview, isShowing: isHovering)
        .accessibilityLabel(isActive ? "Current note: \(tab.displayTitle)" : "Note: \(tab.displayTitle)")
        .onDrag {
            drop.begin(dragging: entry)
            return NSItemProvider(object: SiteDragPayload.encodeRailNote(tab.note.id) as NSString)
        }
        .padding(.vertical, Theme.Metrics.railRowSpacing / 2)
        .overlay(alignment: .top) {
            RailInsertionLine(drop: drop, entry: entry, isBelow: false)
        }
        .overlay(alignment: .bottom) {
            RailInsertionLine(drop: drop, entry: entry, isBelow: true)
        }
        .onDrop(
            of: [SiteDragPayload.type],
            delegate: RailReorderDropDelegate(
                target: entry,
                controller: controller,
                drop: drop,
                rowHeight: Theme.Metrics.railRowHeight
            )
        )
        // Outside `.onDrag`, for the same reason as the session row: a
        // control nested inside a draggable view never receives its click.
        .overlay(alignment: .topTrailing) {
            if isHovering {
                RailCloseButton(
                    tooltip: "Close note (the file is kept)",
                    label: "Close note",
                    keepVisible: { isHovering = true },
                    action: { controller.closeNote(tab.note.id) }
                )
            }
        }
        .contextMenu {
            Button("Open") { controller.openNoteTab(tab.note.id) }

            Divider()

            Button("Move Up") {
                controller.moveRailEntry(entry, by: -1)
            }
            .disabled(!canMoveUp)
            Button("Move Down") {
                controller.moveRailEntry(entry, by: 1)
            }
            .disabled(!canMoveDown)

            Divider()

            Button("Close Note") { controller.closeNote(tab.note.id) }

            Divider()

            // The one note action that removes the file, so it reads and
            // confirms exactly as it does on the Home tile.
            Button(NoteDeletion.menuTitle, role: .destructive) {
                isConfirmingDelete = true
            }
        }
        .confirmNoteDeletion(title: tab.displayTitle, isPresented: $isConfirmingDelete) {
            controller.deleteNote(tab.note.id)
        }
    }

}

/// The accent bar showing where a dragged rail item will land.
private struct RailInsertionLine: View {
    @ObservedObject var drop: RailDropCoordinator
    let entry: RailEntry
    let isBelow: Bool

    var body: some View {
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
            case .note(let id): .note(id)
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
            drop.pointerMoved(
                over: target,
                isBelow: isBelow,
                in: controller.railGroup(containing: target)
            )
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

/// The hover ✕ shared by every rail row.
///
/// Must be attached *after* the row's `.onDrag`: a control nested inside a
/// draggable view never sees its own mouse-down on macOS. `keepVisible`
/// lets the row hold its hover state while the pointer is on the badge,
/// which overhangs the row's corner -- otherwise the ✕ can vanish out from
/// under the click that was aimed at it.
private struct RailCloseButton: View {
    let tooltip: String
    let label: String
    let keepVisible: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.ink, Theme.cardHover)
                // A 11pt glyph is a poor target; the frame gives it one
                // without making the badge look bigger.
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { keepVisible() }
        }
        .help(tooltip)
        .accessibilityLabel(label)
        .offset(x: 4, y: -2)
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
