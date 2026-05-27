import Foundation

public enum HotKeyModifier: UInt32, CaseIterable, Sendable {
    case command = 256
    case shift = 512
    case option = 2048
    case control = 4096

    public static func mask(_ modifiers: [HotKeyModifier]) -> UInt32 {
        modifiers.reduce(UInt32(0)) { partial, modifier in
            partial | modifier.rawValue
        }
    }

    static func labels(for mask: UInt32) -> [String] {
        displayOrder.compactMap { modifier in
            mask & modifier.rawValue == 0 ? nil : modifier.label
        }
    }

    private var label: String {
        switch self {
        case .control:
            "Control"
        case .option:
            "Option"
        case .command:
            "Command"
        case .shift:
            "Shift"
        }
    }

    private static let displayOrder: [HotKeyModifier] = [.control, .option, .command, .shift]
}

public enum HotKeyValidationResult: Equatable, Sendable {
    case valid
    case missingKey
    case modifierOnly
    case missingPrimaryModifier

    public var userMessage: String {
        switch self {
        case .valid:
            ""
        case .missingKey:
            "Press a non-modifier key."
        case .modifierOnly:
            "Use a letter, number, function, or navigation key with modifiers."
        case .missingPrimaryModifier:
            "Use Command, Control, or Option with the key."
        }
    }
}

public struct HotKey: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let keyLabel: String

    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init?(preferenceValue: String) {
        let parts = preferenceValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == "v1",
              let keyCode = UInt32(parts[1]),
              let modifiers = UInt32(parts[2]),
              let keyData = Data(base64Encoded: String(parts[3])),
              let keyLabel = String(data: keyData, encoding: .utf8) else {
            return nil
        }

        self.init(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
    }

    public var label: String {
        (HotKeyModifier.labels(for: modifiers) + [keyLabel]).joined(separator: " ")
    }

    public var preferenceValue: String {
        let encodedKey = Data(keyLabel.utf8).base64EncodedString()
        return "v1:\(keyCode):\(modifiers):\(encodedKey)"
    }

    public var validationResult: HotKeyValidationResult {
        guard !keyLabel.isEmpty else {
            return .missingKey
        }

        guard !Self.modifierOnlyKeyCodes.contains(keyCode) else {
            return .modifierOnly
        }

        let primaryModifierMask = HotKeyModifier.mask([.control, .option, .command])
        guard modifiers & primaryModifierMask != 0 else {
            return .missingPrimaryModifier
        }

        return .valid
    }

    private static let modifierOnlyKeyCodes: Set<UInt32> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63
    ]
}

public enum HotKeyPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case controlOptionCommandS
    case controlOptionCommandOne
    case controlOptionCommandTwo
    case controlOptionCommandFive

    public var id: String { rawValue }

    public var label: String {
        hotKey.label
    }

    public var hotKey: HotKey {
        switch self {
        case .controlOptionCommandS:
            HotKey(
                keyCode: 1,
                modifiers: HotKeyModifier.mask([.control, .option, .command]),
                keyLabel: "S"
            )
        case .controlOptionCommandOne:
            HotKey(
                keyCode: 18,
                modifiers: HotKeyModifier.mask([.control, .option, .command]),
                keyLabel: "1"
            )
        case .controlOptionCommandTwo:
            HotKey(
                keyCode: 19,
                modifiers: HotKeyModifier.mask([.control, .option, .command]),
                keyLabel: "2"
            )
        case .controlOptionCommandFive:
            HotKey(
                keyCode: 23,
                modifiers: HotKeyModifier.mask([.control, .option, .command]),
                keyLabel: "5"
            )
        }
    }
}

public enum HotKeyPreference {
    public static let defaultPreset = HotKeyPreset.controlOptionCommandS
    public static let immediateCaptureDefaultPreset = HotKeyPreset.controlOptionCommandTwo
    public static let cmdTabImmediateCaptureDefaultPreset = HotKeyPreset.controlOptionCommandOne

    public static func resolve(customHotKeyRaw: String?, presetRaw: String?) -> HotKey {
        resolve(customHotKeyRaw: customHotKeyRaw, presetRaw: presetRaw, defaultPreset: defaultPreset)
    }

    public static func resolve(
        customHotKeyRaw: String?,
        presetRaw: String?,
        defaultPreset: HotKeyPreset
    ) -> HotKey {
        if let customHotKeyRaw,
           let customHotKey = HotKey(preferenceValue: customHotKeyRaw),
           customHotKey.validationResult == .valid {
            return customHotKey
        }

        return HotKeyPreset(rawValue: presetRaw ?? "")?.hotKey ?? defaultPreset.hotKey
    }
}
