import SwiftUI

/// Long enough to feel deliberate, shorter than AppKit's own delay: this
/// tooltip exists to answer "what is this glyph?" quickly. A file-level
/// constant because `NoteIconButton` is generic, and generic types cannot
/// hold static stored properties.
private let noteTooltipHoverDelay = Duration.milliseconds(450)

/// Icon-only control shared by the note header and the Markdown toolbar.
///
/// The panel's rail already has this behaviour (`RailIconButton`), and the
/// note chrome has to match it: a fixed hit target, a hover fill, a pressed
/// state, a tooltip, and an accessibility label. Bare glyphs with no hover
/// feedback read as decoration rather than controls, and their tooltip is
/// the only place a shortcut like ⇧⌘P can announce itself.
///
/// The tooltip is Ledge's own (`noteTooltip(_:isShowing:)`) rather than
/// `.help()`: AppKit only draws `toolTip` for the active app, and the panel
/// is routinely on screen while Ledge sits in the background. The label
/// still reaches assistive technology through `accessibilityHint`, which
/// maps to the same accessibility help attribute `.help()` used to set.
struct NoteIconButton<Content: View>: View {
    /// Tooltip text. Include the keyboard shortcut when the action has one.
    let tooltip: String
    /// Accessibility label, without the shortcut.
    let label: String
    /// Draws the control as active -- used by the preview toggle, which is a
    /// switch rather than a one-shot action.
    var isOn: Bool = false
    /// Colour the glyph takes while hovered. Destructive controls use it to
    /// warn before the click, not after.
    var hoverTint: Color?
    /// The note chrome is mouse-driven and every action of consequence has
    /// a shortcut or a menu item, so these controls stay out of the
    /// keyboard focus ring by default. Left focusable, they collect focus
    /// whenever the text view cannot take it -- in preview mode, say --
    /// and paint a blue ring around a bare glyph, which reads as a defect
    /// rather than as a control. VoiceOver still reaches them: this
    /// changes focus, not the accessibility tree.
    var isFocusable: Bool = false
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false
    /// Set once the pointer has settled, so sweeping the pointer across the
    /// row does not fire a trail of bubbles.
    @State private var showsTooltip = false
    @State private var tooltipTask: Task<Void, Never>?



    private var foreground: Color {
        if isHovering, let hoverTint { return hoverTint }
        // An "on" switch is shown by its fill, not by a blue glyph: the
        // note header sits beside plain ink text, and one accent-coloured
        // icon in it looks like a stray selection.
        return isOn ? Theme.ink : Theme.inkSecondary
    }

    var body: some View {
        Button(action: action) {
            content()
                .foregroundStyle(foreground)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoteIconButtonStyle(isHovering: isHovering, isOn: isOn))
        .onHover { hovering in
            isHovering = hovering
            tooltipTask?.cancel()
            guard hovering else {
                showsTooltip = false
                return
            }
            tooltipTask = Task { @MainActor in
                try? await Task.sleep(for: noteTooltipHoverDelay)
                guard !Task.isCancelled else { return }
                showsTooltip = true
            }
        }
        .onDisappear {
            // A control can vanish mid-hover -- the toolbar row is removed
            // when the preview opens -- and its bubble must go with it.
            tooltipTask?.cancel()
            showsTooltip = false
        }
        .noteTooltip(tooltip, isShowing: showsTooltip)
        .accessibilityLabel(label)
        .accessibilityHint(tooltip)
        .focusable(isFocusable)
    }
}

/// Hover and pressed fills, matching the rail's control feedback.
private struct NoteIconButtonStyle: ButtonStyle {
    let isHovering: Bool
    let isOn: Bool

    private var fill: Color {
        if isOn { return Theme.controlPressed }
        return isHovering ? Theme.controlHover : .clear
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Theme.controlPressed : fill)
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
