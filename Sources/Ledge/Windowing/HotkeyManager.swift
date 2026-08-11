import Carbon
import Foundation

/// Uses the legacy Carbon registration API because it provides true global
/// application hotkeys without asking for Accessibility permission.
///
/// One manager owns every shortcut in `GlobalShortcut`: Carbon delivers all
/// hotkey events to the same dispatcher target, so a per-shortcut handler
/// would fire every action on every press. The single handler below reads the
/// `EventHotKeyID` back off the event and runs only the matching action.
final class HotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotkeys: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]

    /// Ledge's Carbon signature ("SSHF"), shared by every shortcut it owns.
    private static let signature = OSType(0x53534846)

    /// Shortcuts `RegisterEventHotKey` actually accepted. Some other app may
    /// already own a combination (Spotlight's alternate binding, another
    /// launcher, …); Settings surfaces the failures instead of letting the
    /// shortcut silently do nothing.
    @MainActor private var registered: Set<GlobalShortcut> = []

    @MainActor
    func isRegistered(_ shortcut: GlobalShortcut) -> Bool {
        registered.contains(shortcut)
    }

    /// Shortcuts that could not be claimed, in declaration order.
    @MainActor
    var unavailableShortcuts: [GlobalShortcut] {
        GlobalShortcut.allCases.filter { !registered.contains($0) }
    }

    /// Claims `shortcut` system-wide. `action` is invoked on whichever thread
    /// Carbon dispatches on, so callers hop to the main actor themselves.
    @MainActor
    @discardableResult
    func register(_ shortcut: GlobalShortcut, action: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else { return false }

        hotkeys[shortcut.rawValue] = reference
        actions[shortcut.rawValue] = action
        registered.insert(shortcut)
        return true
    }

    @MainActor
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, identifier.signature == HotkeyManager.signature else { return noErr }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.perform(identifier.id)
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )
    }

    private func perform(_ identifier: UInt32) {
        actions[identifier]?()
    }

    deinit {
        for hotkey in hotkeys.values { UnregisterEventHotKey(hotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
