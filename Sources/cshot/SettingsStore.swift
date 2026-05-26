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
        hotKeyPresetRaw = defaults.string(forKey: "hotKeyPresetRaw") ?? HotKeyPreset.controlOptionCommandS.rawValue
        captureSoundsEnabled = defaults.object(forKey: "captureSoundsEnabled") as? Bool ?? true
    }

    var effectiveStorageDirectory: String {
        let trimmed = storageDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmed.isEmpty ? "/tmp/agent-shots" : trimmed
        return (path as NSString).expandingTildeInPath
    }

    var injectionMode: InjectionMode {
        InjectionMode(rawValue: injectionModeRaw) ?? .smart
    }

    var hotKeyPreset: HotKeyPreset {
        HotKeyPreset(rawValue: hotKeyPresetRaw) ?? .controlOptionCommandS
    }

    var hotKey: HotKey {
        hotKeyPreset.hotKey
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
