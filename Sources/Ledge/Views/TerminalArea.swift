import AppKit
import Combine
import SwiftUI

/// Terminal-mode main pane: the visible terminal tab with its splits.
///
/// Always mounted (see `LauncherShell`), so every running shell's view stays
/// in the window while another row is shown.
struct TerminalArea: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var terminalController: TerminalController
    @ObservedObject var preferences: Preferences

    var body: some View {
        TerminalHostView(
            controller: controller,
            terminalController: terminalController,
            tabs: terminalController.tabs,
            activeID: controller.activeTerminalID,
            appearance: preferences.terminalAppearance.nsAppearance,
            fontSize: preferences.terminalFontSize
        )
    }
}

/// What a pane's title bar and the notice over a failed pane can do.
private struct TerminalPaneActions {
    let focus: (_ shellID: UUID, _ tabID: UUID) -> Void
    let restart: (_ shellID: UUID, _ tabID: UUID) -> Void
    /// Asks first while the pane is running a command.
    let requestClose: (_ shellID: UUID, _ tabID: UUID) -> Void
    /// Closes without asking: only for a pane whose shell has ended.
    let close: (_ shellID: UUID, _ tabID: UUID) -> Void
}

/// A split pane's title bar: which shell the pane holds, and a ✕ that
/// closes only that pane. Clicking the bar focuses its pane. The focused
/// pane's bar is raised, matching the dimming over the panes around it.
private struct TerminalPaneHeader: View {
    @ObservedObject var tab: TerminalTab
    let shell: TerminalShell
    let focus: () -> Void
    let close: () -> Void

    @State private var isHoveringClose = false

    private var isFocused: Bool { tab.focusedShellID == shell.id }

    var body: some View {
        let label = shell.paneLabel
        HStack(spacing: 2) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(
                        isHoveringClose ? Theme.controlHover : .clear,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFocused ? Theme.inkSecondary : Theme.inkTertiary)
            .onHover { isHoveringClose = $0 }
            .help("Close pane")
            .accessibilityLabel("Close pane: \(label.title)")

            Button(action: focus) {
                HStack(spacing: 6) {
                    Text(label.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isFocused ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    if let detail = label.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkTertiary)
                            .lineLimit(1)
                            // A path keeps its end, which is the part that differs.
                            .truncationMode(.head)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(shell.summary)
            .accessibilityLabel(isFocused ? "Focused pane: \(label.title)" : "Pane: \(label.title)")
            .accessibilityAddTraits(isFocused ? .isSelected : [])
        }
        .padding(.leading, 3)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isFocused ? Theme.card : Theme.card.opacity(0.35),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

/// Shown over a pane whose shell has ended, which only stays open when the
/// shell failed: a clean exit closes the pane. Hosted in AppKit, over its own
/// pane, so it never covers a neighbour that is still in use.
private struct TerminalExitNotice: View {
    @ObservedObject var shell: TerminalShell
    let restart: () -> Void
    let close: () -> Void

    private var message: String? {
        guard case .exited(let status) = shell.state else { return nil }
        guard let status else { return "The shell ended unexpectedly." }
        return "The shell exited with status \(status)."
    }

    var body: some View {
        if let message {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.inkSecondary)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Restart", action: restart)
                Button("Close", action: close)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.controlCornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
            .padding(12)
            .accessibilityElement(children: .contain)
        }
    }
}

/// Hosts one `TerminalTabView` per terminal tab, adding each exactly once and
/// thereafter only toggling `isHidden`, like `SessionHostView`.
private struct TerminalHostView: NSViewRepresentable {
    let controller: PanelController
    let terminalController: TerminalController
    let tabs: [TerminalTab]
    let activeID: UUID?
    let appearance: NSAppearance?
    let fontSize: Double

    func makeNSView(context: Context) -> TerminalHostContainerView {
        let view = TerminalHostContainerView(actions: TerminalPaneActions(
            focus: { [weak controller] in controller?.focusTerminalPane($0, in: $1) },
            restart: { [weak controller] in controller?.restartTerminalPane($0, in: $1) },
            requestClose: { [weak controller] in controller?.requestCloseTerminalPane($0, in: $1) },
            close: { [weak controller] in controller?.closeTerminalPane($0, in: $1) }
        ))
        terminalController.presenter = { [weak view] in view?.present($0) }
        return view
    }

    func updateNSView(_ nsView: TerminalHostContainerView, context: Context) {
        if nsView.appearance?.name != appearance?.name {
            nsView.appearance = appearance
        }
        nsView.apply(tabs: tabs, activeID: activeID, fontSize: fontSize)
    }
}

/// Draws the terminal background, and sets the appearance every terminal
/// inside resolves its colours against.
private final class TerminalHostContainerView: NSView {
    /// Space between the pane area's edge and the panes. The trailing side is
    /// narrower because each terminal draws its own scroller there.
    private static let insets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 4)

    private let actions: TerminalPaneActions
    private var tabViews: [UUID: TerminalTabView] = [:]
    private var shownID: UUID?
    private var fontSize = TerminalFontSize.standard

    init(actions: TerminalPaneActions) {
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    /// Runs with this view's appearance current, so the dynamic colour
    /// resolves to the terminal's light or dark canvas.
    override func updateLayer() {
        layer?.backgroundColor = Theme.NS.canvas.cgColor
    }

    override func layout() {
        super.layout()
        let insets = Self.insets
        let content = NSRect(
            x: bounds.minX + insets.left,
            y: bounds.minY + insets.bottom,
            width: max(bounds.width - insets.left - insets.right, 0),
            height: max(bounds.height - insets.top - insets.bottom, 0)
        )
        for tabView in tabViews.values {
            tabView.frame = content
        }
    }

    func apply(tabs: [TerminalTab], activeID: UUID?, fontSize: Double) {
        self.fontSize = fontSize
        for tab in tabs {
            tabView(for: tab).update(fontSize: fontSize)
        }
        let live = Set(tabs.map(\.id))
        for (id, tabView) in tabViews where !live.contains(id) {
            resignFocus(from: tabView)
            tabView.removeFromSuperview()
            tabViews[id] = nil
        }

        // `present` normally shows a tab first. Getting here with a new tab
        // means it was presented before this view existed, so it still needs
        // focus -- once this update has put its views in the window.
        guard show(activeID), let activeView = activeID.flatMap({ tabViews[$0] }) else { return }
        DispatchQueue.main.async { [weak activeView] in
            guard let activeView, !activeView.isHidden, let focused = activeView.focusedView else { return }
            focused.window?.makeFirstResponder(focused)
        }
    }

    /// Shows `tab` and focuses its focused pane now, ahead of SwiftUI's next
    /// update, so keys typed straight away reach it.
    func present(_ tab: TerminalTab) {
        let tabView = tabView(for: tab)
        tabView.update(fontSize: fontSize)
        show(tab.id)
        layoutSubtreeIfNeeded()
        if let focused = tabView.focusedView {
            window?.makeFirstResponder(focused)
        }
    }

    /// Shows tab `id` alone, or none. Returns whether that changed which tab
    /// is shown.
    @discardableResult
    private func show(_ id: UUID?) -> Bool {
        for (tabID, tabView) in tabViews {
            let isShown = tabID == id
            if !isShown, !tabView.isHidden {
                resignFocus(from: tabView)
            }
            tabView.isHidden = !isShown
        }
        defer { shownID = id }
        return shownID != id
    }

    private func tabView(for tab: TerminalTab) -> TerminalTabView {
        if let existing = tabViews[tab.id] { return existing }
        let tabView = TerminalTabView(tab: tab, actions: actions)
        tabView.isHidden = true
        addSubview(tabView)
        tabViews[tab.id] = tabView
        needsLayout = true
        return tabView
    }

    /// Keystrokes must never reach a terminal the user cannot see.
    private func resignFocus(from view: NSView) {
        guard let window, let responder = window.firstResponder as? NSView,
              responder === view || responder.isDescendant(of: view) else { return }
        window.makeFirstResponder(nil)
    }
}

/// One terminal tab's panes: each shell's view laid out by the tab's split
/// tree, with draggable dividers between them, a title bar over each pane
/// once there is more than one, the unfocused panes dimmed, and a notice over
/// any pane whose shell has failed.
private final class TerminalTabView: NSView {
    /// The gap between two panes, all of it a target for dragging the
    /// divider; only a hairline in its middle is drawn.
    static let dividerThickness: CGFloat = 9
    /// The failed-shell notice and the margin around it.
    static let noticeHeight: CGFloat = 64

    let tab: TerminalTab
    private let actions: TerminalPaneActions
    private var dividerViews: [TerminalDividerView] = []
    private var headerViews: [UUID: NSView] = [:]
    private var dimViews: [UUID: TerminalDimView] = [:]
    private var noticeViews: [UUID: NSView] = [:]
    /// Divider positions mid-drag, published to the tab only on release so a
    /// drag does not re-render the rest of the panel at every step.
    private var draggedFractions: [UUID: Double] = [:]
    private var fontSize = TerminalFontSize.standard
    private var tabObservation: AnyCancellable?

    init(tab: TerminalTab, actions: TerminalPaneActions) {
        self.tab = tab
        self.actions = actions
        super.init(frame: .zero)
        // Focus, splits, and restarted shells change the tab, not anything
        // SwiftUI passes to `TerminalHostView`, so SwiftUI has no reason to
        // update this view for them. `objectWillChange` fires before the
        // change lands; the run-loop hop reads the changed tab.
        tabObservation = tab.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.update(fontSize: self.fontSize)
            }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The split tree's geometry puts the first pane of a stacked split on top.
    override var isFlipped: Bool { true }

    var focusedView: NSView? { tab.focusedShell.view }

    /// Brings the subviews in line with the tab's shells.
    func update(fontSize: Double) {
        self.fontSize = fontSize
        let shells = tab.orderedShells
        var live = Set<ObjectIdentifier>()
        for shell in shells {
            guard let view = shell.view else { continue }
            live.insert(ObjectIdentifier(view))
            if view.superview !== self {
                view.translatesAutoresizingMaskIntoConstraints = true
                // Beneath the dimming, the dividers, and the notices.
                addSubview(view, positioned: .below, relativeTo: nil)
            }
            // A pane running a command keeps its size until it is back at the
            // prompt; see `LedgeTerminalView.setFontSize`. Finishing the
            // command changes the shell, which runs this again.
            if shell.runningCommand == nil {
                view.setFontSize(fontSize)
            }
        }
        for view in subviews where view is LedgeTerminalView && !live.contains(ObjectIdentifier(view)) {
            view.removeFromSuperview()
        }

        let ids = Set(shells.map(\.id))
        for (id, dim) in dimViews where !ids.contains(id) {
            dim.removeFromSuperview()
            dimViews[id] = nil
        }
        for id in ids where dimViews[id] == nil {
            let dim = TerminalDimView()
            addSubview(dim)
            dimViews[id] = dim
        }

        let titled = tab.isSplit ? ids : []
        for (id, header) in headerViews where !titled.contains(id) {
            header.removeFromSuperview()
            headerViews[id] = nil
        }
        for shell in shells where titled.contains(shell.id) && headerViews[shell.id] == nil {
            let (shellID, tabID, actions) = (shell.id, tab.id, actions)
            let header = NSHostingView(rootView: TerminalPaneHeader(
                tab: tab,
                shell: shell,
                focus: { actions.focus(shellID, tabID) },
                close: { actions.requestClose(shellID, tabID) }
            ))
            // Sized by `layout()` alone.
            header.sizingOptions = []
            addSubview(header)
            headerViews[shellID] = header
        }

        let failed = Set(shells.filter { if case .exited = $0.state { true } else { false } }.map(\.id))
        for (id, notice) in noticeViews where !failed.contains(id) {
            notice.removeFromSuperview()
            noticeViews[id] = nil
        }
        for shell in shells where failed.contains(shell.id) && noticeViews[shell.id] == nil {
            let (shellID, tabID, actions) = (shell.id, tab.id, actions)
            let notice = NSHostingView(rootView: TerminalExitNotice(
                shell: shell,
                restart: { actions.restart(shellID, tabID) },
                close: { actions.close(shellID, tabID) }
            ))
            addSubview(notice)
            noticeViews[shellID] = notice
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let thickness = tab.isSplit ? Self.dividerThickness : 0
        let layout = draggedFractions.reduce(tab.layout) { $0.settingFraction($1.value, forSplit: $1.key) }
        let geometry = layout.geometry(in: bounds, dividerThickness: thickness)

        for pane in geometry.panes {
            let frames = TerminalPaneChrome.frames(for: pane.frame, showsHeader: tab.isSplit)
            tab.shell(for: pane.id)?.view?.frame = frames.terminal
            if let header = headerViews[pane.id], let frame = frames.header {
                header.frame = frame
            }
            if let dim = dimViews[pane.id] {
                dim.frame = frames.terminal
                dim.isHidden = !tab.isSplit || pane.id == tab.focusedShellID
            }
            if let notice = noticeViews[pane.id] {
                let terminal = frames.terminal
                let height = min(Self.noticeHeight, terminal.height)
                notice.frame = NSRect(x: terminal.minX, y: terminal.maxY - height, width: terminal.width, height: height)
            }
        }

        while dividerViews.count > geometry.dividers.count {
            dividerViews.removeLast().removeFromSuperview()
        }
        while dividerViews.count < geometry.dividers.count {
            let divider = TerminalDividerView()
            divider.onDrag = { [weak self] splitID, fraction, isFinished in
                guard let self else { return }
                if isFinished {
                    self.draggedFractions[splitID] = nil
                    self.tab.setFraction(fraction, forSplit: splitID)
                } else {
                    self.draggedFractions[splitID] = fraction
                }
                self.needsLayout = true
                self.layoutSubtreeIfNeeded()
            }
            addSubview(divider)
            dividerViews.append(divider)
        }
        for (view, divider) in zip(dividerViews, geometry.dividers) {
            view.divider = divider
            view.frame = divider.frame
        }
    }
}

/// The draggable gap between two panes. Double-clicking evens the split.
private final class TerminalDividerView: NSView {
    private var lastFraction: Double?
    var divider: TerminalGeometry.Divider? {
        didSet {
            guard divider?.orientation != oldValue?.orientation else { return }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    /// The split, the fraction under the pointer, and whether the drag ended.
    var onDrag: ((UUID, Double, Bool) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        guard let divider else { return }
        Theme.NS.hairline.setFill()
        let line = switch divider.orientation {
        case .sideBySide: NSRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: bounds.height)
        case .stacked: NSRect(x: bounds.minX, y: bounds.midY - 0.5, width: bounds.width, height: 1)
        }
        line.fill()
    }

    override func resetCursorRects() {
        guard let divider else { return }
        addCursorRect(bounds, cursor: divider.orientation == .sideBySide ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        lastFraction = nil
        guard event.clickCount == 2, let divider else { return }
        onDrag?(divider.splitID, 0.5, true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let divider, let superview else { return }
        let fraction = divider.fraction(at: superview.convert(event.locationInWindow, from: nil))
        lastFraction = fraction
        onDrag?(divider.splitID, fraction, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard let divider, let fraction = lastFraction else { return }
        lastFraction = nil
        onDrag?(divider.splitID, fraction, true)
    }
}

/// Dims an unfocused pane, so the one taking keystrokes stands out. Clicks
/// pass straight through to the terminal beneath.
private final class TerminalDimView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.NS.canvas.cgColor.copy(alpha: 0.4)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
