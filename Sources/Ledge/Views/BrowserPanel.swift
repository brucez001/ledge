import AppKit
import SwiftUI

/// Browser-mode main pane: the web content fills the pane, with the browser
/// chrome (home/back/forward/reload/address/overflow) floating over the top of
/// it rather than taking a permanent 52pt slice out of a panel that is already
/// narrow.
///
/// The chrome appears when the pointer approaches the top of the page, while
/// the address field is being edited, or on ⌘L, and slides away again
/// otherwise. "Always show the browser toolbar" in Settings pins it open for
/// anyone who prefers the old behaviour. The find bar and the error banner are
/// independent of it -- they show whenever they have something to say.
///
/// Always mounted (see `LauncherShell`) so its web views are never torn down;
/// the toolbar is likewise never unmounted, only moved out of sight, so the
/// address field keeps its `AddressField` coordinator and focus behaviour.
struct BrowserPanel: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject private var preferences: Preferences

    @State private var isHoveringTop = false
    @State private var isEditingAddress = false
    /// Set by ⌘L so the chrome is on screen before the field takes focus.
    @State private var isRevealedByCommand = false

    init(controller: PanelController, sessionManager: SessionManager) {
        self.controller = controller
        self.sessionManager = sessionManager
        self.preferences = controller.preferences
    }

    private var showsChrome: Bool {
        preferences.pinsBrowserToolbar
            || isHoveringTop
            || controller.isPointerNearPanelTop
            || isEditingAddress
            || isRevealedByCommand
    }

    private var chromeHeight: CGFloat {
        Theme.Metrics.toolbarHeight
    }

    /// While the chrome is showing, the hover strip has to cover the chrome
    /// itself -- otherwise moving the pointer down onto the toolbar would
    /// leave the strip and flicker it away again.
    private var topHoverHeight: CGFloat {
        showsChrome ? chromeHeight + 12 : 14
    }

    var body: some View {
        ZStack(alignment: .top) {
            SessionHostView(
                sessionManager: sessionManager,
                topHoverHeight: preferences.pinsBrowserToolbar ? 0 : topHoverHeight,
                onTopHoverChange: { isHoveringTop = $0 }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.contentCornerRadius, style: .continuous))
            .padding(6)

            if let session = sessionManager.activeSession() {
                chrome(for: session)
            }
        }
        .background(Theme.canvas)
        .onChange(of: controller.addressFocusToken) { _, _ in
            isRevealedByCommand = true
        }
        .onChange(of: isEditingAddress) { _, editing in
            // Once the field is done, the chrome goes back to following the
            // pointer instead of staying pinned by the earlier ⌘L.
            if !editing { isRevealedByCommand = false }
        }
        .onChange(of: controller.destination) { _, _ in
            isHoveringTop = false
            isRevealedByCommand = false
        }
    }

    @ViewBuilder
    private func chrome(for session: WebSession) -> some View {
        VStack(spacing: 0) {
            // A floating card rather than a docked bar: it sits *over* the
            // page, so it needs its own opaque backing and edge to stay
            // legible against arbitrary site colours.
            BrowserToolbar(
                controller: controller,
                session: session,
                isEditingAddress: $isEditingAddress
            )
            .id(session.id)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Metrics.contentCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.contentCornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            // Never unmounted, only moved out of sight, so the address field
            // keeps its coordinator, its focus, and its editing state.
            .offset(y: showsChrome ? 0 : -(chromeHeight + 14))
            .opacity(showsChrome ? 1 : 0)
            .allowsHitTesting(showsChrome)
            .animation(.easeOut(duration: 0.16), value: showsChrome)

            // A page can be loading with the chrome hidden, so the progress
            // line lives outside it and stays pinned to the top edge.
            ProgressView(value: session.estimatedProgress)
                .progressViewStyle(.linear)
                .frame(height: 2)
                .opacity(session.isLoading ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: session.isLoading)

            if controller.isShowingFindBar {
                FindBar(controller: controller, session: session)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Metrics.contentCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let message = session.loadErrorMessage {
                ErrorBanner(message: message, retry: session.reload) {
                    session.loadErrorMessage = nil
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.contentCornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .animation(.easeOut(duration: 0.18), value: controller.isShowingFindBar)
        .animation(.easeOut(duration: 0.18), value: session.loadErrorMessage)
    }
}

/// Distinct home control (separated from the back/forward cluster), back/
/// forward, a reload/stop toggle, a single flexible address pill, and a
/// trailing overflow menu. The page title deliberately lives only in the
/// overflow menu header -- a narrow panel has no room for it in the row.
struct BrowserToolbar: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var session: WebSession
    /// Lifted out of the toolbar so `BrowserPanel` can keep the chrome on
    /// screen for as long as the address field is being edited.
    @Binding var isEditingAddress: Bool

    @State private var addressText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            iconButton("house.fill", help: "Home", label: "Home", action: controller.goHome)

            HStack(spacing: 2) {
                iconButton("chevron.left", help: "Back", label: "Back", action: session.goBack)
                    .disabled(!session.canGoBack)
                iconButton("chevron.right", help: "Forward", label: "Forward", action: session.goForward)
                    .disabled(!session.canGoForward)
            }

            iconButton(
                session.isLoading ? "xmark" : "arrow.clockwise",
                help: session.isLoading ? "Stop" : "Reload",
                label: session.isLoading ? "Stop loading" : "Reload",
                action: session.reloadOrStop
            )

            addressPill

            Menu {
                overflowMenuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            // Suppress the "⌄" `.borderlessButton` otherwise appends to the
            // label -- the toolbar is tight, and every other control here is a
            // single bare glyph.
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Theme.inkSecondary)
            .help("More actions")
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.toolbarHeight)
        .onAppear {
            addressText = session.currentURL?.absoluteString ?? ""
        }
        .onChange(of: session.currentURL) { _, newValue in
            // Keep the field synced with navigation (didStartProvisional/
            // didCommit/didFinish all update `currentURL`), but never stomp
            // text the user is actively editing.
            guard !isEditingAddress, let newValue else { return }
            addressText = newValue.absoluteString
        }
    }

    private func iconButton(_ systemName: String, help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.inkSecondary)
        .help(help)
        .accessibilityLabel(label)
    }

    // MARK: - Address pill

    private var addressPill: some View {
        HStack(spacing: 8) {
            Image(systemName: session.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(session.isSecure ? Theme.inkSecondary : .orange)
                .accessibilityHidden(true)

            AddressField(
                text: addressBinding,
                placeholder: "Address",
                focusToken: controller.addressFocusToken,
                onSubmit: commitAddress,
                onFocusChange: handleFocusChange
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.addressPillHeight)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: Capsule())
    }

    /// While unfocused, the field shows the tidy `displayHost`; while
    /// focused, it shows (and edits) the full URL in `addressText`.
    private var addressBinding: Binding<String> {
        Binding(
            get: { isEditingAddress ? addressText : session.displayHost },
            set: { addressText = $0 }
        )
    }

    private func handleFocusChange(_ focused: Bool) {
        isEditingAddress = focused
        if focused {
            addressText = session.currentURL?.absoluteString ?? addressText
        }
    }

    private func commitAddress() {
        guard let url = AddressResolver.resolve(addressText) else { return }
        session.load(url)
        isEditingAddress = false
    }

    // MARK: - Overflow menu

    private var zoomPercentText: String {
        "\(Int((session.zoom * 100).rounded()))%"
    }

    @ViewBuilder
    private var overflowMenuContent: some View {
        if !session.pageTitle.isEmpty {
            Text(session.pageTitle)
            Divider()
        }

        Button("Copy address") { session.copyCurrentURL() }
        Button("Open in default browser") { session.openInDefaultBrowser() }

        if controller.canAddCurrentPageToSidebar {
            Button("Add to Sidebar") { controller.addCurrentPageToSidebar() }
        }

        Divider()

        Button("Find…") { controller.toggleFindBar() }
            .keyboardShortcut("f", modifiers: [.command])

        Divider()

        if let favourite = controller.activeFavourite {
            Button(favourite.resolvedUserAgentMode.toggled.title) {
                controller.setUserAgentMode(favourite.resolvedUserAgentMode.toggled, for: favourite)
            }
            Toggle(
                "Reload when shown",
                isOn: Binding(
                    get: { favourite.resolvedReloadsOnFocus },
                    set: { controller.setReloadsOnFocus($0, for: favourite) }
                )
            )
        } else {
            Button(session.userAgentMode.toggled.title) {
                session.setUserAgentMode(session.userAgentMode.toggled)
            }
        }

        Divider()

        Button("Zoom In") { session.zoomIn() }
        Button("Zoom Out") { session.zoomOut() }
        Button("Reset Zoom (\(zoomPercentText))") { session.resetZoom() }

        Divider()

        Button("Pause media") { session.pauseMedia() }

        if controller.activeFavourite != nil {
            Button("Close live session", role: .destructive) {
                controller.closeActiveSession()
            }
        }
    }
}

/// Inline, dismissible banner for a failed navigation. Sits above the web
/// content rather than as a modal alert, so the panel never blocks on it.
private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.dangerInk)

            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.dangerInk)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Retry", action: retry)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dangerInk)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.dangerInk.opacity(0.7))
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.dangerSurface)
    }
}

/// AppKit-backed address field. Plain SwiftUI `TextField` + `FocusState`
/// cannot reliably select existing text on demand, but this app's most
/// important focus interaction (opening a favourite from the rail, or
/// bumping `addressFocusToken` generally) needs exactly that -- focus
/// *and* select-all, like every real browser's address bar.
private struct AddressField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: Int
    var onSubmit: () -> Void
    var onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingMiddle
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Re-bind the coordinator each update: its closures capture the
        // session/controller from the render that created it, and a stale
        // `onSubmit` would load a URL into the wrong session.
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        guard context.coordinator.lastFocusToken != focusToken else { return }
        context.coordinator.lastFocusToken = focusToken
        // The field must already be in its window before it can become
        // first responder; a same-runloop-turn attempt silently no-ops.
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
            nsView.currentEditor()?.selectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressField
        var lastFocusToken = -1

        init(_ parent: AddressField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                control.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}
