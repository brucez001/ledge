import AppKit

/// A borderless panel has to opt into becoming key before SwiftUI text fields
/// can receive focus.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
