import AppKit
import SwiftUI

/// A region that moves the panel when dragged.
///
/// The panel deliberately does not use `isMovableByWindowBackground`: that
/// AppKit behaviour claims drag gestures before SwiftUI sees them, so dragging
/// a site to reorder it moved the whole window instead. Moving the panel is
/// therefore an explicit gesture on this handle, which forwards the mouse-down
/// to `NSWindow.performDrag(with:)` -- still a real window drag, so the
/// edge-snapping and position persistence in `PanelController`'s window
/// delegate continue to work unchanged.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragRegionView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
