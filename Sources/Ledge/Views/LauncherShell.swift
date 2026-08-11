import SwiftUI

/// Root content view for the panel. The main pane (home + browser) is
/// always mounted -- collapsing only fades/shrinks it -- so the live
/// `WKWebView`s hosted inside `BrowserPanel` are never structurally
/// removed from the view hierarchy.
struct LauncherShell: View {
    @ObservedObject var controller: PanelController
    @ObservedObject private var favourites: FavouritesStore
    @ObservedObject private var sessionManager: SessionManager
    /// Pulled out (rather than read as `controller.preferences...`) so
    /// changes made in Settings while the panel is open -- animation
    /// speed in particular -- take effect immediately.
    @ObservedObject private var preferences: Preferences

    init(controller: PanelController) {
        self.controller = controller
        self.favourites = controller.favourites
        self.sessionManager = controller.sessionManager
        self.preferences = controller.preferences
    }

    var body: some View {
        HStack(spacing: 0) {
            if controller.dockSide == .left {
                AppRail(controller: controller)
                Rectangle().fill(Theme.hairline).frame(width: 1)
            }

            ZStack {
                LauncherHome(
                    controller: controller,
                    favourites: favourites,
                    preferences: preferences
                )
                    .opacity(controller.showsStartPage ? 1 : 0)
                    .allowsHitTesting(controller.showsStartPage)

                BrowserPanel(controller: controller, sessionManager: sessionManager)
                    .opacity(controller.showsStartPage ? 0 : 1)
                    .allowsHitTesting(!controller.showsStartPage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if controller.dockSide == .right {
                Rectangle().fill(Theme.hairline).frame(width: 1)
                AppRail(controller: controller)
            }
        }
        .background {
            // Vibrancy first so the panel reads as native macOS chrome
            // rather than a flat rectangle pasted over the desktop, with
            // `Theme.canvas` tinted on top (at reduced opacity so the blur
            // still shows through at the edges).
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                Theme.canvas.opacity(0.88)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.panelCornerRadius, style: .continuous)
                .stroke(Theme.panelBorder, lineWidth: 1)
        }
        // No SwiftUI drop shadow here: the panel content fills the window
        // exactly, so a shadow would be clipped to the window bounds and only
        // smudge the rounded corner cut-outs. The real shadow comes from the
        // window itself (`panel.hasShadow`), which follows the drawn shape.
        .animation(preferences.animationSpeed.contentAnimation, value: controller.destination)
        .animation(preferences.animationSpeed.contentAnimation, value: controller.dockSide)
        .sheet(isPresented: $controller.isShowingAddFavourite) {
            AddFavouriteSheet(store: favourites)
        }
    }
}
