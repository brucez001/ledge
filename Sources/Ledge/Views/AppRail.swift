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

    private var tabIDs: [UUID] {
        sessionManager.tabSessions.compactMap(\.id.tabID)
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

            Divider().padding(.horizontal, 10)

            sites

            Divider().padding(.horizontal, 10)

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
    private var sites: some View {
        ScrollView(.vertical) {
            VStack(spacing: 4) {
                ForEach(favourites.items) { item in
                    RailSiteButton(
                        controller: controller,
                        item: item,
                        isActive: controller.destination == .favourite(item.id),
                        hasSession: sessionManager.hasSession(forFavouriteID: item.id)
                    )
                }

                // Transient tabs follow the saved sites. Deliberately *not*
                // separated by a rule: with a rail full of similar icons an
                // extra full-width line reads as arbitrary clutter rather than
                // as grouping. Position plus the close button on hover is
                // enough to tell a tab from a saved site.
                ForEach(tabIDs, id: \.self) { id in
                    RailTabButton(
                        controller: controller,
                        tabID: id,
                        isActive: controller.destination == .tab(id),
                        isBlank: controller.blankTabIDs.contains(id)
                    )
                }

                RailIconButton(
                    systemName: "plus",
                    label: "New tab",
                    tooltip: "New tab (⌘T)",
                    action: { controller.newTab() }
                )
            }
        }
        .scrollIndicators(.hidden)
        // Takes the space left between the fixed controls above and below, so
        // a long list scrolls instead of pushing them off the rail.
        .frame(maxHeight: .infinity, alignment: .top)
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
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius, style: .continuous)
                        .fill(isHoveringOptions ? Theme.controlHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        // Without this, `.borderlessButton` still draws a disclosure chevron
        // beside the label -- it renders as "···⌄", which crowds a 56pt rail
        // and pushes the glyph off centre.
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
/// under a 36pt icon in a narrow rail reads as a stray artefact rather than as
/// feedback, and any drag that ends without a `dropExited` strands it on
/// screen. The rail now shows no such marker in any state.
private struct RailSiteButton: View {
    @ObservedObject var controller: PanelController
    let item: Favourite
    let isActive: Bool
    let hasSession: Bool

    @State private var isHovering = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        Button {
            controller.openFavourite(item)
        } label: {
            FaviconView(host: item.host, size: 26)
                .frame(width: 26, height: 26)
                .padding(4)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(RailButtonBackgroundStyle(isHovering: isHovering, isSelected: isActive))
        .onHover { isHovering = $0 }
        .help(item.name)
        .accessibilityLabel("Open \(item.name)")
        .onDrag {
            NSItemProvider(object: SiteDragPayload.encode(item.id) as NSString)
        }
        .onDrop(
            of: [SiteDragPayload.type],
            delegate: SiteReorderDropDelegate(
                target: item,
                controller: controller,
                rowHeight: 36
            )
        )
        .contextMenu {
            Button("Open") { controller.openFavourite(item) }
            if hasSession {
                Button("Reload") { controller.sessionManager.session(forFavourite: item).reload() }
            }

            Divider()

            Button(item.resolvedUserAgentMode.toggled.title) {
                controller.setUserAgentMode(item.resolvedUserAgentMode.toggled, for: item)
            }
            Toggle(
                "Reload when shown",
                isOn: Binding(
                    get: { item.resolvedReloadsOnFocus },
                    set: { controller.setReloadsOnFocus($0, for: item) }
                )
            )
            Button("Copy address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.address, forType: .string)
            }

            Divider()

            // Keyboard/menu reordering as well as dragging: a 36pt target in a
            // narrow rail is a fiddly thing to hit precisely.
            Button("Move Up") { controller.favourites.moveUp(id: item.id) }
                .disabled(controller.favourites.items.first?.id == item.id)
            Button("Move Down") { controller.favourites.moveDown(id: item.id) }
                .disabled(controller.favourites.items.last?.id == item.id)

            if hasSession {
                Divider()
                Button("Close live session") {
                    controller.sessionManager.closeSession(kind: .favourite(item.id))
                }
            }

            Divider()

            Button("Remove from sidebar…", role: .destructive) {
                isConfirmingRemoval = true
            }
        }
        .confirmationDialog(
            "Remove \(item.name)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { controller.removeFavourite(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also closes its live session. Signed-in cookies are kept.")
        }
    }
}

/// Turns a drop on a rail row into an insert-above or insert-below.
///
/// It accepts two kinds of payload: a saved site being reordered, and a
/// transient tab being dragged into the saved sites to pin it at that exact
/// position.
private struct SiteReorderDropDelegate: DropDelegate {
    let target: Favourite
    let controller: PanelController
    let rowHeight: CGFloat

    private var favourites: FavouritesStore { controller.favourites }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [SiteDragPayload.type])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let placement = proposedInsertion(for: info)

        guard let provider = info.itemProviders(for: [SiteDragPayload.type]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let string = reading as? String,
                  let item = SiteDragPayload.decodeItem(string) else { return }
            Task { @MainActor in
                switch item {
                case .site(let id):
                    if placement.isBelow {
                        favourites.move(id: id, after: placement.targetID)
                    } else {
                        favourites.move(id: id, before: placement.targetID)
                    }
                case .tab(let id):
                    // Dropping a tab among the saved sites pins it, keeping its
                    // live page, at the position it was dropped.
                    controller.pinTab(id, placement: placement)
                }
            }
        }
        return true
    }

    private func proposedInsertion(for info: DropInfo) -> SiteDropInsertion {
        SiteDropInsertion(targetID: target.id, isBelow: info.location.y > rowHeight / 2)
    }
}

/// One transient tab in the rail. It shows a placeholder glyph until the tab
/// has been navigated somewhere, then the site's own icon.
private struct RailTabButton: View {
    @ObservedObject var controller: PanelController
    let tabID: UUID
    let isActive: Bool
    let isBlank: Bool

    @State private var isHovering = false

    private var session: WebSession? {
        controller.sessionManager.existingSession(for: .tab(tabID))
    }

    private var host: String {
        session?.displayHost ?? ""
    }

    private var tooltip: String {
        if isBlank { return "New tab" }
        let title = session?.pageTitle ?? ""
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
                    FaviconView(host: host, size: 26)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 36, height: 36)
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
        // Draggable so a tab can be dropped among the saved sites to pin it
        // there. An empty tab has nothing to pin, so it is not offered.
        .onDrag(
            if: !isBlank,
            payload: { NSItemProvider(object: SiteDragPayload.encodeTab(tabID) as NSString) }
        )
        .contextMenu {
            if controller.canAddCurrentPageToSidebar, isActive {
                Button("Add to Sidebar") { controller.addCurrentPageToSidebar() }
                Divider()
            }
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
                .frame(width: 30, height: 28)
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
