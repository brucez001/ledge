import AppKit
import SwiftUI

/// Configures the AppKit window that SwiftUI creates for the `Settings` scene.
///
/// SwiftUI does not expose that window directly. A zero-size backing view can
/// reach it without affecting the Settings layout.
struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowAdoptingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowAdoptingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.level = WindowLayering.settings
            window.collectionBehavior.insert(.moveToActiveSpace)

            guard SettingsPresentation.shouldDismissPresentation() else { return }
            // SwiftUI orders this window in and starts its open animation
            // before this runs, so closing it here is swallowed by the
            // in-flight presentation and the window stays up. The close has to
            // wait a turn, and until it lands the window must not draw, or the
            // panel flashes up and vanishes at every launch.
            window.alphaValue = 0
            Task { @MainActor in
                window.close()
                // Restored for the next requested open, which reuses this
                // same window.
                window.alphaValue = 1
            }
        }
    }
}
