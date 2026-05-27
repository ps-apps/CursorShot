import cshotCore
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let changedNotification = Notification.Name("cshotSettingsChanged")

    @Published var storageDirectory: String {
        didSet { persist("storageDirectory", value: storageDirectory) }
    }

    @Published var retentionDays: Int {
        didSet { persist("retentionDays", value: retentionDays) }
    }

    @Published var injectionModeRaw: String {
        didSet { persist("injectionModeRaw", value: injectionModeRaw) }
    }

    @Published var hotKeyPresetRaw: String {
        didSet { persist("hotKeyPresetRaw", value: hotKeyPresetRaw) }
    }

    @Published var customHotKeyRaw: String {
        didSet { persist("customHotKeyRaw", value: customHotKeyRaw) }
    }

    @Published var immediateCaptureHotKeyPresetRaw: String {
        didSet { persist("immediateCaptureHotKeyPresetRaw", value: immediateCaptureHotKeyPresetRaw) }
    }

    @Published var immediateCaptureHotKeyRaw: String {
        didSet { persist("immediateCaptureHotKeyRaw", value: immediateCaptureHotKeyRaw) }
    }

    @Published var currentSpaceCaptureTargetRaw: String {
        didSet { persist("currentSpaceCaptureTargetRaw", value: currentSpaceCaptureTargetRaw) }
    }

    @Published var cmdTabCaptureHotKeyPresetRaw: String {
        didSet { persist("cmdTabCaptureHotKeyPresetRaw", value: cmdTabCaptureHotKeyPresetRaw) }
    }

    @Published var cmdTabCaptureHotKeyRaw: String {
        didSet { persist("cmdTabCaptureHotKeyRaw", value: cmdTabCaptureHotKeyRaw) }
    }

    @Published var captureSoundsEnabled: Bool {
        didSet { persist("captureSoundsEnabled", value: captureSoundsEnabled) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storageDirectory = defaults.string(forKey: "storageDirectory") ?? "/tmp/agent-shots"

        if let storedRetentionDays = defaults.object(forKey: "retentionDays") as? Int {
            retentionDays = max(1, storedRetentionDays)
        } else {
            retentionDays = 7
        }

        injectionModeRaw = defaults.string(forKey: "injectionModeRaw") ?? InjectionMode.smart.rawValue
        hotKeyPresetRaw = defaults.string(forKey: "hotKeyPresetRaw") ?? HotKeyPreference.defaultPreset.rawValue
        customHotKeyRaw = defaults.string(forKey: "customHotKeyRaw") ?? ""
        immediateCaptureHotKeyPresetRaw = defaults.string(forKey: "immediateCaptureHotKeyPresetRaw")
            ?? HotKeyPreference.immediateCaptureDefaultPreset.rawValue
        immediateCaptureHotKeyRaw = defaults.string(forKey: "immediateCaptureHotKeyRaw") ?? ""
        let legacyImmediateTargetRaw = defaults.string(forKey: "immediateCaptureTargetRaw")
        currentSpaceCaptureTargetRaw = defaults.string(forKey: "currentSpaceCaptureTargetRaw")
            ?? Self.currentSpaceCaptureTargetRaw(fromLegacyRaw: legacyImmediateTargetRaw)
        cmdTabCaptureHotKeyPresetRaw = defaults.string(forKey: "cmdTabCaptureHotKeyPresetRaw")
            ?? HotKeyPreference.cmdTabImmediateCaptureDefaultPreset.rawValue
        cmdTabCaptureHotKeyRaw = defaults.string(forKey: "cmdTabCaptureHotKeyRaw") ?? ""
        captureSoundsEnabled = defaults.object(forKey: "captureSoundsEnabled") as? Bool ?? true
        let debugMessage = "settings loaded defaultHotKey=\(hotKey.label) currentSpaceHotKey=\(immediateCaptureHotKey.label) currentSpaceTarget=\(currentSpaceCaptureTarget.rawValue) cmdTabHotKey=\(cmdTabCaptureHotKey.label) storage=\(effectiveStorageDirectory)"
        DebugLog.write(debugMessage)
    }

    var effectiveStorageDirectory: String {
        let trimmed = storageDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmed.isEmpty ? "/tmp/agent-shots" : trimmed
        return (path as NSString).expandingTildeInPath
    }

    var injectionMode: InjectionMode {
        InjectionMode(rawValue: injectionModeRaw) ?? .smart
    }

    var hotKey: HotKey {
        HotKeyPreference.resolve(customHotKeyRaw: customHotKeyRaw, presetRaw: hotKeyPresetRaw)
    }

    var immediateCaptureHotKey: HotKey {
        HotKeyPreference.resolve(
            customHotKeyRaw: immediateCaptureHotKeyRaw,
            presetRaw: immediateCaptureHotKeyPresetRaw,
            defaultPreset: HotKeyPreference.immediateCaptureDefaultPreset
        )
    }

    var currentSpaceCaptureTarget: CurrentSpaceCaptureTarget {
        CurrentSpaceCaptureTarget(rawValue: currentSpaceCaptureTargetRaw) ?? .topApp
    }

    var cmdTabCaptureHotKey: HotKey {
        HotKeyPreference.resolve(
            customHotKeyRaw: cmdTabCaptureHotKeyRaw,
            presetRaw: cmdTabCaptureHotKeyPresetRaw,
            defaultPreset: HotKeyPreference.cmdTabImmediateCaptureDefaultPreset
        )
    }

    func assignHotKey(_ hotKey: HotKey) {
        customHotKeyRaw = hotKey.preferenceValue
    }

    func assignImmediateCaptureHotKey(_ hotKey: HotKey) {
        immediateCaptureHotKeyRaw = hotKey.preferenceValue
    }

    func assignCmdTabCaptureHotKey(_ hotKey: HotKey) {
        cmdTabCaptureHotKeyRaw = hotKey.preferenceValue
    }

    func resetHotKeyToDefault() {
        customHotKeyRaw = ""
        hotKeyPresetRaw = HotKeyPreference.defaultPreset.rawValue
    }

    func resetImmediateCaptureHotKeyToDefault() {
        immediateCaptureHotKeyRaw = ""
        immediateCaptureHotKeyPresetRaw = HotKeyPreference.immediateCaptureDefaultPreset.rawValue
    }

    func resetCmdTabCaptureHotKeyToDefault() {
        cmdTabCaptureHotKeyRaw = ""
        cmdTabCaptureHotKeyPresetRaw = HotKeyPreference.cmdTabImmediateCaptureDefaultPreset.rawValue
    }

    private static func currentSpaceCaptureTargetRaw(fromLegacyRaw raw: String?) -> String {
        switch raw {
        case "currentApp":
            CurrentSpaceCaptureTarget.currentApp.rawValue
        case "nextApp":
            CurrentSpaceCaptureTarget.topApp.rawValue
        default:
            CurrentSpaceCaptureTarget.topApp.rawValue
        }
    }

    private func persist(_ key: String, value: String) {
        defaults.set(value, forKey: key)
        notifyChanged()
    }

    private func persist(_ key: String, value: Int) {
        defaults.set(max(1, value), forKey: key)
        notifyChanged()
    }

    private func persist(_ key: String, value: Bool) {
        defaults.set(value, forKey: key)
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }
}
