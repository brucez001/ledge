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
        }
    }
}
