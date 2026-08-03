import Carbon
import Foundation

/// Uses the legacy Carbon registration API because it provides a true global
/// application hotkey without asking for Accessibility permission.
final class HotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotkey: EventHotKeyRef?
    private let action: () -> Void
    /// Whether `RegisterEventHotKey` actually succeeded. Some other app may
    /// already own ⇧⌘Space (Spotlight's alternate binding, another
    /// launcher, …); Settings surfaces this instead of the hotkey silently
    /// doing nothing.
    @MainActor private(set) var isRegistered = false

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @MainActor
    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.action()
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )

        let identifier = EventHotKeyID(signature: OSType(0x53534846), id: 1) // "SSHF"
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            identifier,
            GetEventDispatcherTarget(),
            0,
            &hotkey
        )
        isRegistered = status == noErr
    }

    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
