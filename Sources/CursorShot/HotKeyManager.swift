import Carbon
import CursorShotCore
import Foundation

private let cursorShotHotKeySignature: OSType = 0x43534854
nonisolated(unsafe) private var cursorShotHotKeyEventHandlerRef: EventHandlerRef?
nonisolated(unsafe) private var cursorShotHotKeyManagers: [UInt32: HotKeyManager] = [:]

private let cursorShotHotKeyCallback: EventHandlerUPP = { _, event, _ in
    guard let hotKeyID = cursorShotHotKeyID(from: event) else {
        DebugLog.write("hotkey callback ignored: missing/foreign hotkey id")
        return noErr
    }

    let id = hotKeyID.id
    DebugLog.write("hotkey callback received id=\(id)")
    DispatchQueue.main.async {
        cursorShotHotKeyManagers[id]?.fire()
    }
    return noErr
}

final class HotKeyManager: @unchecked Sendable {
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    init(id: UInt32) {
        self.id = id
    }

    @discardableResult
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) -> HotKeyRegistrationError? {
        unregister()
        self.handler = handler
        DebugLog.write("register hotkey id=\(id) keyCode=\(hotKey.keyCode) modifiers=\(hotKey.modifiers)")

        if let installStatus = installCursorShotHotKeyEventHandlerIfNeeded() {
            self.handler = nil
            DebugLog.write("install hotkey handler failed id=\(id) status=\(installStatus)")
            return HotKeyRegistrationError(hotKey: hotKey, status: installStatus)
        }

        cursorShotHotKeyManagers[id] = self

        let hotKeyID = EventHotKeyID(signature: cursorShotHotKeySignature, id: id)
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            DebugLog.write("register hotkey failed id=\(id) status=\(registerStatus)")
            unregister()
            return HotKeyRegistrationError(hotKey: hotKey, status: registerStatus)
        }

        DebugLog.write("register hotkey succeeded id=\(id)")
        return nil
    }

    func unregister() {
        if let hotKeyRef {
            DebugLog.write("unregister hotkey id=\(id)")
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        handler = nil
        cursorShotHotKeyManagers[id] = nil
    }

    deinit {
        unregister()
    }

    fileprivate func fire() {
        DebugLog.write("fire hotkey id=\(id) hasHandler=\(handler != nil)")
        handler?()
    }
}

private func installCursorShotHotKeyEventHandlerIfNeeded() -> OSStatus? {
    guard cursorShotHotKeyEventHandlerRef == nil else {
        return nil
    }

    var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    let status = InstallEventHandler(
        GetApplicationEventTarget(),
        cursorShotHotKeyCallback,
        1,
        &eventType,
        nil,
        &cursorShotHotKeyEventHandlerRef
    )

    return status == noErr ? nil : status
}

private func cursorShotHotKeyID(from event: EventRef?) -> EventHotKeyID? {
    guard let event else {
        return nil
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == cursorShotHotKeySignature else {
        return nil
    }

    return hotKeyID
}

struct HotKeyRegistrationError: LocalizedError {
    let hotKey: HotKey
    let status: OSStatus

    var errorDescription: String? {
        "Could not register \(hotKey.label) as a global shortcut. Pick another shortcut in Settings. macOS returned status \(status)."
    }
}
