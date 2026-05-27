import Carbon
import cshotCore
import Foundation

private let cshotHotKeySignature: OSType = 0x43534854
nonisolated(unsafe) private var cshotHotKeyEventHandlerRef: EventHandlerRef?
nonisolated(unsafe) private var cshotHotKeyManagers: [UInt32: HotKeyManager] = [:]

private let cshotHotKeyCallback: EventHandlerUPP = { _, event, _ in
    guard let hotKeyID = cshotHotKeyID(from: event) else {
        DebugLog.write("hotkey callback ignored: missing/foreign hotkey id")
        return noErr
    }

    let id = hotKeyID.id
    DebugLog.write("hotkey callback received id=\(id)")
    DispatchQueue.main.async {
        cshotHotKeyManagers[id]?.fire()
    }
    return noErr
}

final class HotKeyManager: @unchecked Sendable {
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    init(id: UInt32 = 1) {
        self.id = id
    }

    @discardableResult
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) -> HotKeyRegistrationError? {
        unregister()
        self.handler = handler
        DebugLog.write("register hotkey id=\(id) label='\(hotKey.label)' keyCode=\(hotKey.keyCode) modifiers=\(hotKey.modifiers)")

        if let installStatus = installcshotHotKeyEventHandlerIfNeeded() {
            self.handler = nil
            DebugLog.write("install hotkey handler failed id=\(id) status=\(installStatus)")
            return HotKeyRegistrationError(hotKey: hotKey, status: installStatus)
        }

        cshotHotKeyManagers[id] = self

        let hotKeyID = EventHotKeyID(signature: cshotHotKeySignature, id: id)
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
        cshotHotKeyManagers[id] = nil
    }

    deinit {
        unregister()
    }

    fileprivate func fire() {
        DebugLog.write("fire hotkey id=\(id) hasHandler=\(handler != nil)")
        handler?()
    }
}

private func installcshotHotKeyEventHandlerIfNeeded() -> OSStatus? {
    guard cshotHotKeyEventHandlerRef == nil else {
        return nil
    }

    var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    let status = InstallEventHandler(
        GetApplicationEventTarget(),
        cshotHotKeyCallback,
        1,
        &eventType,
        nil,
        &cshotHotKeyEventHandlerRef
    )

    return status == noErr ? nil : status
}

private func cshotHotKeyID(from event: EventRef?) -> EventHotKeyID? {
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
    guard status == noErr, hotKeyID.signature == cshotHotKeySignature else {
        return nil
    }

    return hotKeyID
}

struct HotKeyRegistrationError: LocalizedError {
    let hotKey: HotKey
    let status: OSStatus

    var errorDescription: String? {
        "Could not register \(hotKey.label) as the global hotkey. Pick another shortcut in Settings. macOS returned status \(status)."
    }
}
