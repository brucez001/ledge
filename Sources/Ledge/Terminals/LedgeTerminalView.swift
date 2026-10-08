import AppKit
import SwiftTerm

/// SwiftTerm's local-process view, styled to sit on the panel's canvas and
/// reporting the two events Ledge reacts to: output arriving and the shell
/// exiting on its own.
final class LedgeTerminalView: LocalProcessTerminalView {
    /// Rows kept above the screen. SwiftTerm's own default is 500, which a
    /// single build log overruns.
    static let scrollback = 10_000

    var onOutput: (() -> Void)?
    var onShellExit: ((Int32?) -> Void)?
    var onClick: (() -> Void)?

    static func make(fontSize: Double = TerminalFontSize.standard) -> LedgeTerminalView {
        let view = LedgeTerminalView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 400),
            font: font(ofSize: fontSize),
            options: TerminalOptions(scrollback: scrollback)
        )
        // Terminal's default: Option types the characters many keyboard
        // layouts need it for, such as `@`, `|`, and `€`.
        view.optionAsMetaKey = false
        view.applyAppearance()
        return view
    }

    private static func font(ofSize size: Double) -> NSFont {
        .monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    /// SwiftTerm soft-resets the terminal whenever its font changes, which
    /// drops cursor, keypad, and scroll-region modes a full-screen program has
    /// set; callers only change it while the shell is at its prompt.
    func setFontSize(_ size: Double) {
        guard font.pointSize != CGFloat(size) else { return }
        font = Self.font(ofSize: size)
    }

    /// Whether halving this terminal along `orientation` leaves both halves
    /// usable. A shell that has not drawn yet always may be split.
    func canSplit(_ orientation: TerminalSplitOrientation) -> Bool {
        let terminal = getTerminal()
        switch orientation {
        case .sideBySide: return terminal.cols >= 2 * 20 + 1
        case .stacked: return terminal.rows >= 2 * 5 + 1
        }
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
    }

    /// Types `event` and returns `true` if it is a keypad key that
    /// `TerminalKeypad` handles or a text-editing shortcut that
    /// `TerminalLineEditing` handles. SwiftTerm's `keyDown` cannot be
    /// overridden, so the panel's key monitor calls this first.
    func typeTranslatedKey(_ event: NSEvent) -> Bool {
        let terminal = getTerminal()
        let kittyKeyboard = !terminal.keyboardEnhancementFlags.isEmpty
        if let text = TerminalKeypad.text(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            characters: event.characters,
            kittyKeyboard: kittyKeyboard
        ) {
            selection.active = false
            send(txt: text)
            return true
        }
        // An input method composing text owns the editing keys.
        guard !hasMarkedText(), let bytes = TerminalLineEditing.bytes(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            kittyKeyboard: kittyKeyboard,
            alternateScreen: terminal.isCurrentBufferAlternate
        ) else { return false }
        selection.active = false
        send(bytes)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        // SwiftTerm waits on the shell once, without blocking, and reports 0
        // when that wait fails -- which it can when the exit event arrives
        // before the shell is waitable. Waiting again tells the cases apart.
        let pid = source.shellPid
        var status: Int32 = 0
        switch waitpid(pid, &status, WNOHANG) {
        case pid:
            onShellExit?(Self.exitStatus(fromWaitStatus: status))
        case 0:
            DispatchQueue.global(qos: .utility).async { [weak self] in
                var status: Int32 = 0
                let exit = waitpid(pid, &status, 0) == pid ? Self.exitStatus(fromWaitStatus: status) : nil
                Task { @MainActor in self?.onShellExit?(exit) }
            }
        default:
            // SwiftTerm's own wait succeeded.
            onShellExit?(exitCode.flatMap(Self.exitStatus(fromWaitStatus:)))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    /// SwiftTerm copies colours into the terminal when they are assigned, so
    /// the panel's dynamic colours are resolved for the current appearance
    /// here and again whenever it changes.
    private func applyAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeBackgroundColor = Self.resolved(Theme.NS.canvas)
            nativeForegroundColor = Self.resolved(Theme.NS.ink)
            caretColor = Self.resolved(.controlAccentColor)
        }
        installColors(Self.palette(isDark: isDark))
    }

    private static func resolved(_ color: NSColor) -> NSColor {
        NSColor(cgColor: color.cgColor) ?? color
    }

    /// The 16 ANSI colours. xterm's own palette is drawn for a black screen:
    /// on the light canvas its cyan, yellow, and white wash out, so light
    /// appearance gets darker variants.
    static func palette(isDark: Bool) -> [SwiftTerm.Color] {
        let hex: [UInt32] = isDark
            ? [0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
               0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF]
            : [0x000000, 0xC91B00, 0x0F7B0F, 0x8F7A00, 0x0451A5, 0xBC05BC, 0x0E7C86, 0x6E6E6E,
               0x5C5C5C, 0xE0352B, 0x14A314, 0xA68A00, 0x1E6FD9, 0xC838C6, 0x0598BC, 0x8A8A8A]
        return hex.map {
            SwiftTerm.Color(
                red8: UInt16(($0 >> 16) & 0xFF),
                green8: UInt16(($0 >> 8) & 0xFF),
                blue8: UInt16($0 & 0xFF)
            )
        }
    }

    /// SwiftTerm reports the raw `waitpid` status. A shell killed by a signal
    /// has no exit status, and is reported as `nil`.
    nonisolated static func exitStatus(fromWaitStatus status: Int32) -> Int32? {
        let signal = status & 0x7f
        guard signal == 0 else { return nil }
        return (status >> 8) & 0xff
    }
}
