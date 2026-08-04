import SwiftUI

/// The dock rail: a vertical strip of the user's saved sites, plus the panel's
/// own controls.
///
/// This deliberately reverses an earlier decision that the rail should carry
/// only panel controls, with sites living exclusively on the home screen.
/// Switching between sites is the most frequent thing anyone does with a
/// slide-over, and routing every switch through the home grid made it a
/// two-step trip. Sites now appear here the moment they are added; the home
/// screen remains the place to search, and to rename/reorder/remove.
struct AppRail: View {
    @ObservedObject var controller: PanelController
    @ObservedObject private var favourites: FavouritesStore
    @ObservedObject private var sessionManager: SessionManager

    /// `Menu` cannot take a `ButtonStyle`, so its hover feedback has to be
    /// applied to the label by hand to match the other rail controls.
    @State private var isHoveringOptions = false

    init(controller: PanelController) {
        self.controller = controller
        self.favourites = controller.favourites
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

    /// Saved sites and transient tabs in one order, so either can be moved
    /// anywhere among the other.
    private var entries: [RailEntry] {
        controller.railEntries
    }

    /// The only place that moves the panel, now that dragging the background
    /// is off (it used to swallow the reorder gesture).
    private var dragHandle: some View {
        WindowDragHandle()
            .frame(height: 14)
            .overlay {
                Capsule()
                    .fill(Theme.inkTertiary)
                    .frame(width: 18, height: 3)
                    // Must not steal the mouse-down from the AppKit view below.
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
                tooltip: "Search and manage sites",
                isOn: controller.destination == .home,
                action: controller.goHome
            )

            Divider().padding(.horizontal, 7)

            sites

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
            // The rail's empty space doubles as the window-drag region, so
            // moving the panel is forgiving rather than a 14pt target. It sits
            // *behind* the controls, so the buttons and their own drag
            // gestures (reordering a site) still win.
            ZStack {
                Theme.rail
                WindowDragHandle()
            }
        }
    }

    /// The site list scrolls, so a long list never squeezes out the controls
    /// pinned above and below it.
    ///
    /// Saved sites and tabs share one list and one reordering rule. They used to
    /// be two consecutive stretches, which made a tab's position unexpressible:
    /// order came from the persisted favourites array for one and from session
    /// creation order for the other, so the only way to move a tab up among the
    /// saved sites was to convert it into one.
    private var sites: some View {
        ScrollView(.vertical) {
            // Spacing lives inside each row (as padding it can claim for its
            // drop target) rather than between them, so the 4pt seams are no
            // longer dead zones that swallow a drop.
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    row(for: entry)
                }

                // A control rather than a row, so it sits slightly apart and is
                // not a drop target.
                RailIconButton(
                    systemName: "plus",
                    label: "New tab",
                    tooltip: "New tab (⌘T)",
                    action: { controller.newTab() }
                )
                .padding(.top, entries.isEmpty ? 0 : 6)
            }
        }
        .scrollIndicators(.hidden)
        // Takes the space left between the fixed controls above and below, so
        // a long list scrolls instead of pushing them off the rail.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func row(for entry: RailEntry) -> some View {
        let canMoveUp = entries.first != entry
        let canMoveDown = entries.last != entry

        switch entry {
        case .favourite(let id):
            if let item = favourites.items.first(where: { $0.id == id }) {
                RailSiteButton(
                    controller: controller,
                    item: item,
                    isActive: controller.destination == .favourite(id),
                    hasSession: sessionManager.hasSession(forFavouriteID: id),
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown
                )
            }
        case .tab(let id):
            RailTabButton(
                controller: controller,
                tabID: id,
                isActive: controller.destination == .tab(id),
                isBlank: controller.blankTabIDs.contains(id),
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown
            )
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button("Add Site…") {
                controller.openAddFavourite()
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

            Button("Dock Left") {
                controller.setDockSide(.left)
            }
            .disabled(controller.dockSide == .left)

            Button("Dock Right") {
                controller.setDockSide(.right)
            }
            .disabled(controller.dockSide == .right)

            Divider()

            // `SettingsLink` is the supported way to open the `Settings`
            // scene from SwiftUI; the AppKit status-bar menu has to fall
            // back to `sendAction` because no equivalent exists there.
            SettingsLink {
                Text("Settings…")
            }

            Divider()

            Button("Quit Ledge") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis")
                // Matches `RailIconButton`'s metrics and weight exactly; this
                // used to be a heavier, differently sized glyph.
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
        // Without this, `.borderlessButton` still draws a disclosure chevron
        // beside the label -- it renders as "···⌄", which crowds a rail this
        // narrow and pushes the glyph off centre.
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHoveringOptions = $0 }
        .help("Ledge options")
        .accessibilityLabel("Ledge options")
    }
}

/// One site in the rail: its icon and the same context menu the home-screen
/// tile offers.
///
/// Reordering uses a `DropDelegate` rather than a plain `.onDrop` so the drop
/// *location* is available: the upper half of a row means "insert above", the
/// lower half "insert below". Without that, a drop could only ever mean
/// "before this row", which gave no way to move a site to the very end.
///
/// The drop position is deliberately *not* drawn as an accent line: a 2pt rule
/// under a rail-sized icon reads as a stray artefact rather than as feedback,
/// and any drag that ends without a `dropExited` strands it on screen. The rail
/// now shows no such marker in any state.
private struct RailSiteButton: View {
    @ObservedObject var controller: PanelController
    let item: Favourite
    let isActive: Bool
    let hasSession: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    @State private var isHovering = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        Button {
            controller.openFavourite(item)
        } label: {
            FaviconView(host: item.host, size: Theme.Metrics.railIconSize)
                .frame(width: Theme.Metrics.railIconSize, height: Theme.Metrics.railIconSize)
                .padding(4)
                .frame(width: Theme.Metrics.railItemSize, height: Theme.Metrics.railItemSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(RailButtonBackgroundStyle(isHovering: isHovering, isSelected: isActive))
        .onHover { isHovering = $0 }
        .help(item.name)
        .accessibilityLabel("Open \(item.name)")
        .onDrag {
            NSItemProvider(object: SiteDragPayload.encode(item.id) as NSString)
        }
        .padding(.vertical, Theme.Metrics.railRowSpacing / 2)
        .onDrop(
            of: [SiteDragPayload.type],
            delegate: RailReorderDropDelegate(
                target: .favourite(item.id),
                controller: controller,
                rowHeight: Theme.Metrics.railRowHeight
            )
        )
        .contextMenu {
            // Menu reordering as well as dragging: a small target in a narrow
            // rail is a fiddly thing to hit precisely. Moves span the whole
            // rail, so a saved site steps over an interleaved tab as readily as
            // over another saved site.
            FavouriteMenuItems(
                controller: controller,
                item: item,
                hasSession: hasSession,
                reordering: RailReordering(
                    entry: .favourite(item.id),
                    controller: controller,
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown
                )
            ) {
                isConfirmingRemoval = true
            }
        }
        .confirmFavouriteRemoval(item, isPresented: $isConfirmingRemoval) {
            controller.removeFavourite(item)
        }
    }
}

/// Turns a drop on any rail row into an insert-above or insert-below.
///
/// One delegate for both kinds of row, because the rail is one list: a saved
/// site and a tab reorder by the same rule, and a drag never converts one into
/// the other. Keeping a tab is only ever the explicit "Add to Favourites" --
/// position and persistence are separate concerns, and a gesture aimed at the
/// first must not quietly perform the second.
///
/// A `DropDelegate` rather than a plain `.onDrop` so the drop *location* is
/// available: the upper half of a row means "insert above", the lower half
/// "insert below". Without that a drop could only ever mean "before this row",
/// leaving no way to reach the end of the rail.
private struct RailReorderDropDelegate: DropDelegate {
    let target: RailEntry
    let controller: PanelController
    let rowHeight: CGFloat

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [SiteDragPayload.type])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let isBelow = info.location.y > rowHeight / 2

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
}

/// One transient tab in the rail. It shows a placeholder glyph until the tab
/// has been navigated somewhere, then the site's own icon.
///
/// Its context menu deliberately mirrors the saved-site menu wherever the
/// action means the same thing for a tab. A tab used to offer nothing but
/// "Close Tab", which made the rail feel as though right-clicking only worked
/// on some of its icons; everything a live session can do (reload, user agent,
/// reload-on-focus, address, reordering) applies equally to a tab. Only the two
/// items that genuinely have no meaning are absent: "Close live session" would
/// duplicate "Close Tab" (closing a tab *is* closing its session), and there is
/// no saved entry to remove -- its counterpart is "Add to Favourites".
private struct RailTabButton: View {
    @ObservedObject var controller: PanelController
    let tabID: UUID
    let isActive: Bool
    let isBlank: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    /// The row needs the session *observed*, not merely fetched: watching
    /// `SessionManager.sessions` does not forward a `WebSession`'s own
    /// `objectWillChange`, so the icon, tooltip, and menu text went stale as a
    /// tab navigated. A tab always has a session -- it is only listed because one
    /// exists -- so the empty branch is unreachable in practice.
    var body: some View {
        if let session = controller.sessionManager.existingSession(for: .tab(tabID)) {
            RailTabRow(
                controller: controller,
                session: session,
                tabID: tabID,
                isActive: isActive,
                isBlank: isBlank,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown
            )
        }
    }
}

private struct RailTabRow: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var session: WebSession
    let tabID: UUID
    let isActive: Bool
    let isBlank: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    @State private var isHovering = false

    private var host: String {
        session.displayHost
    }

    private var tooltip: String {
        if isBlank { return "New tab" }
        let title = session.pageTitle
        return title.isEmpty ? (host.isEmpty ? "Tab" : host) : title
    }

    var body: some View {
        Button {
            controller.openTab(tabID)
        } label: {
            Group {
                if isBlank || host.isEmpty {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .semibold))
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
        // A close affordance on hover is what distinguishes a transient tab
        // from a saved site, now that there is no dividing rule between them.
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    controller.closeTab(tabID)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.ink, Theme.cardHover)
                }
                .buttonStyle(.plain)
                .help("Close tab")
                .accessibilityLabel("Close tab")
                .offset(x: 3, y: -3)
            }
        }
        .onHover { isHovering = $0 }
        .help(tooltip)
        .accessibilityLabel(isBlank ? "New tab" : "Tab: \(tooltip)")
        // A tab drag only ever moves the tab. It never converts it: keeping a
        // site is the explicit "Add to Favourites", so a gesture aimed at
        // position cannot quietly change what the icon is.
        .onDrag {
            NSItemProvider(object: SiteDragPayload.encodeTab(tabID) as NSString)
        }
        .padding(.vertical, Theme.Metrics.railRowSpacing / 2)
        .onDrop(
            of: [SiteDragPayload.type],
            delegate: RailReorderDropDelegate(
                target: .tab(tabID),
                controller: controller,
                rowHeight: Theme.Metrics.railRowHeight
            )
        )
        .contextMenu {
            Button("Open") { controller.openTab(tabID) }

            Button("Reload") { session.reload() }

            Divider()

            Button(session.userAgentMode.toggled.title) {
                session.setUserAgentMode(session.userAgentMode.toggled)
            }
            // Not persisted, unlike a saved site's copy of this setting: a tab
            // is gone at the next launch, so there is nowhere to keep it and
            // nothing to migrate.
            Toggle(
                "Reload when shown",
                isOn: Binding(
                    get: { session.reloadsOnFocus },
                    set: { session.reloadsOnFocus = $0 }
                )
            )
            Button("Copy address") { session.copyCurrentURL() }
                .disabled(session.currentURL == nil)
            Button("Open in default browser") { session.openInDefaultBrowser() }
                .disabled(session.currentURL == nil)

            // Moves span the whole rail: a tab can step above the saved sites
            // and stay a tab. Omitted only when the rail has a single row, where
            // the pair could never do anything.
            if canMoveUp || canMoveDown {
                Divider()

                Button("Move Up") { controller.moveRailEntry(.tab(tabID), by: -1) }
                    .disabled(!canMoveUp)
                Button("Move Down") { controller.moveRailEntry(.tab(tabID), by: 1) }
                    .disabled(!canMoveDown)
            }

            // Offered for any tab with somewhere to go, not just the visible
            // one: `pinTab` works on a tab by id, and asking about the *active*
            // session answered the wrong question when the menu belonged to a
            // tab in the background.
            if controller.canPinTab(tabID) {
                Divider()
                Button("Add to Favourites") { controller.pinTab(tabID) }
            }

            Divider()

            Button("Close Tab") { controller.closeTab(tabID) }
        }
    }
}

/// Shared rail control: a fixed hit target with distinct hover and pressed
/// backgrounds (rather than the previous bare, unfeedback icons), tinted
/// entirely from `Theme` so it reads correctly in both appearances.
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
