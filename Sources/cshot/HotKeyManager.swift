import Carbon
import cshotCore
import Foundation

final class HotKeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    @discardableResult
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) -> HotKeyRegistrationError? {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let manager = Unmanaged<HotKeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()

            DispatchQueue.main.async { [manager] in
                manager.fire()
            }

            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            self.handler = nil
            return HotKeyRegistrationError(hotKey: hotKey, status: installStatus)
        }

        let hotKeyId = EventHotKeyID(signature: 0x43534854, id: 1)
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            return HotKeyRegistrationError(hotKey: hotKey, status: registerStatus)
        }

        return nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }

    private func fire() {
        handler?()
    }
}

struct HotKeyRegistrationError: LocalizedError {
    let hotKey: HotKey
    let status: OSStatus

    var errorDescription: String? {
        "Could not register \(hotKey.label) as the global hotkey. Pick another shortcut in Settings. macOS returned status \(status)."
    }
}
