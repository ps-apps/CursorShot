import CursorShotCore
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let changedNotification = Notification.Name("cursorShotSettingsChanged")

    @Published var storageDirectory: String {
        didSet { persist("storageDirectory", value: storageDirectory) }
    }

    @Published var retentionDays: Int {
        didSet { persist("retentionDays", value: retentionDays) }
    }

    @Published var injectionModeRaw: String {
        didSet { persist("injectionModeRaw", value: injectionModeRaw) }
    }

    @Published var defaultCaptureHotKeyRaw: String {
        didSet { persist("defaultCaptureHotKeyRaw", value: defaultCaptureHotKeyRaw) }
    }

    @Published var cmdTabQuickCaptureHotKeyRaw: String {
        didSet { persist("cmdTabQuickCaptureHotKeyRaw", value: cmdTabQuickCaptureHotKeyRaw) }
    }

    @Published var currentSpaceQuickCaptureHotKeyRaw: String {
        didSet { persist("currentSpaceQuickCaptureHotKeyRaw", value: currentSpaceQuickCaptureHotKeyRaw) }
    }

    @Published var currentSpaceCaptureTargetRaw: String {
        didSet { persist("currentSpaceCaptureTargetRaw", value: currentSpaceCaptureTargetRaw) }
    }

    @Published var captureSoundsEnabled: Bool {
        didSet { persist("captureSoundsEnabled", value: captureSoundsEnabled) }
    }

    @Published var cropModeEnabled: Bool {
        didSet { persist("cropModeEnabled", value: cropModeEnabled) }
    }

    @Published var fullScreenModeEnabled: Bool {
        didSet { persist("fullScreenModeEnabled", value: fullScreenModeEnabled) }
    }

    @Published var annotationModeEnabled: Bool {
        didSet { persist("annotationModeEnabled", value: annotationModeEnabled) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storageDirectory = Self.normalizedStorageDirectory(defaults.string(forKey: "storageDirectory"))

        if let storedRetentionDays = defaults.object(forKey: "retentionDays") as? Int {
            retentionDays = max(1, storedRetentionDays)
        } else {
            retentionDays = 7
        }

        injectionModeRaw = defaults.string(forKey: "injectionModeRaw") ?? InjectionMode.smart.rawValue
        defaultCaptureHotKeyRaw = defaults.string(forKey: "defaultCaptureHotKeyRaw")
            ?? defaults.string(forKey: "customHotKeyRaw")
            ?? ""
        cmdTabQuickCaptureHotKeyRaw = defaults.string(forKey: "cmdTabQuickCaptureHotKeyRaw")
            ?? defaults.string(forKey: "cmdTabCaptureHotKeyRaw")
            ?? ""
        currentSpaceQuickCaptureHotKeyRaw = defaults.string(forKey: "currentSpaceQuickCaptureHotKeyRaw")
            ?? defaults.string(forKey: "immediateCaptureHotKeyRaw")
            ?? ""
        let legacyImmediateTargetRaw = defaults.string(forKey: "immediateCaptureTargetRaw")
        currentSpaceCaptureTargetRaw = defaults.string(forKey: "currentSpaceCaptureTargetRaw")
            ?? Self.currentSpaceCaptureTargetRaw(fromLegacyRaw: legacyImmediateTargetRaw)
        captureSoundsEnabled = defaults.object(forKey: "captureSoundsEnabled") as? Bool ?? true
        cropModeEnabled = defaults.object(forKey: "cropModeEnabled") as? Bool ?? true
        fullScreenModeEnabled = defaults.object(forKey: "fullScreenModeEnabled") as? Bool ?? true
        annotationModeEnabled = defaults.object(forKey: "annotationModeEnabled") as? Bool ?? true
        let debugMessage = "settings loaded defaultShortcut=\(defaultCaptureHotKey.label) cmdTabShortcut=\(cmdTabQuickCaptureHotKey.label) currentSpaceShortcut=\(currentSpaceQuickCaptureHotKey.label) currentSpaceTarget=\(currentSpaceCaptureTarget.rawValue) modes crop=\(cropModeEnabled) fullScreen=\(fullScreenModeEnabled) annotation=\(annotationModeEnabled)"
        DebugLog.write(debugMessage)
    }

    var effectiveStorageDirectory: String {
        (Self.normalizedStorageDirectory(storageDirectory) as NSString).expandingTildeInPath
    }

    var usesManagedStorageDirectory: Bool {
        let effectiveURL = URL(fileURLWithPath: effectiveStorageDirectory, isDirectory: true).standardizedFileURL
        return effectiveURL.path == CaptureStorage.defaultDirectory.standardizedFileURL.path
    }

    var injectionMode: InjectionMode {
        InjectionMode(rawValue: injectionModeRaw) ?? .smart
    }

    var defaultCaptureHotKey: HotKey {
        hotKey(for: .defaultCapture)
    }

    var cmdTabQuickCaptureHotKey: HotKey {
        hotKey(for: .cmdTabQuickCapture)
    }

    var currentSpaceQuickCaptureHotKey: HotKey {
        hotKey(for: .currentSpaceQuickCapture)
    }

    var currentSpaceCaptureTarget: CurrentSpaceCaptureTarget {
        CurrentSpaceCaptureTarget(rawValue: currentSpaceCaptureTargetRaw) ?? .topApp
    }

    var captureOverlayConfiguration: CaptureOverlayConfiguration {
        CaptureOverlayConfiguration(
            cropEnabled: cropModeEnabled,
            fullScreenEnabled: fullScreenModeEnabled,
            annotationEnabled: annotationModeEnabled
        )
    }

    var hotKeyAssignments: [HotKeyAssignment] {
        HotKeyRole.allCases.map { role in
            HotKeyAssignment(role: role, hotKey: hotKey(for: role))
        }
    }

    func hotKey(for role: HotKeyRole) -> HotKey {
        HotKeyPreference.resolve(
            customHotKeyRaw: hotKeyRaw(for: role),
            defaultPreset: role.defaultPreset
        )
    }

    func assignHotKey(_ hotKey: HotKey, to role: HotKeyRole) {
        setHotKeyRaw(hotKey.preferenceValue, for: role)
    }

    func resetHotKey(for role: HotKeyRole) {
        setHotKeyRaw("", for: role)
    }

    func conflictingHotKeyAssignment(assigning hotKey: HotKey, to role: HotKeyRole) -> HotKeyAssignment? {
        HotKeyConflictValidator.conflict(
            assigning: hotKey,
            to: role,
            among: hotKeyAssignments
        )
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

    private static func normalizedStorageDirectory(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed != CaptureStorage.legacyDefaultDirectoryPath else {
            return CaptureStorage.defaultDirectory.path
        }

        return trimmed
    }

    private func hotKeyRaw(for role: HotKeyRole) -> String {
        switch role {
        case .defaultCapture:
            defaultCaptureHotKeyRaw
        case .cmdTabQuickCapture:
            cmdTabQuickCaptureHotKeyRaw
        case .currentSpaceQuickCapture:
            currentSpaceQuickCaptureHotKeyRaw
        }
    }

    private func setHotKeyRaw(_ value: String, for role: HotKeyRole) {
        switch role {
        case .defaultCapture:
            defaultCaptureHotKeyRaw = value
        case .cmdTabQuickCapture:
            cmdTabQuickCaptureHotKeyRaw = value
        case .currentSpaceQuickCapture:
            currentSpaceQuickCaptureHotKeyRaw = value
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
