import Carbon
import Foundation

struct HotKey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String
}

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case controlOptionCommandS
    case controlOptionCommandTwo
    case controlOptionCommandFive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlOptionCommandS:
            "Control Option Command S"
        case .controlOptionCommandTwo:
            "Control Option Command 2"
        case .controlOptionCommandFive:
            "Control Option Command 5"
        }
    }

    var hotKey: HotKey {
        switch self {
        case .controlOptionCommandS:
            HotKey(keyCode: 1, modifiers: UInt32(controlKey | optionKey | cmdKey), label: label)
        case .controlOptionCommandTwo:
            HotKey(keyCode: 19, modifiers: UInt32(controlKey | optionKey | cmdKey), label: label)
        case .controlOptionCommandFive:
            HotKey(keyCode: 23, modifiers: UInt32(controlKey | optionKey | cmdKey), label: label)
        }
    }
}

final class HotKeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    func register(_ hotKey: HotKey, handler: @escaping () -> Void) {
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

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let hotKeyId = EventHotKeyID(signature: 0x43534854, id: 1)
        RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
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
