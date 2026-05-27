import AppKit
import CursorShotCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let defaultCaptureHotKeyManager = HotKeyManager(id: 1)
    private let cmdTabQuickCaptureHotKeyManager = HotKeyManager(id: 2)
    private let currentSpaceQuickCaptureHotKeyManager = HotKeyManager(id: 3)
    private let activationTracker = ApplicationActivationTracker()
    private let errorPresenter = ErrorPresenter()

    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var captureCoordinator: CaptureCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("applicationDidFinishLaunching")
        refreshActivationPolicy()

        settingsWindowController = SettingsWindowController(settings: settings)
        captureCoordinator = CaptureCoordinator(
            settings: settings,
            activationTracker: activationTracker,
            errorPresenter: errorPresenter
        )

        configureAppIcon()
        configureStatusItem()
        registerHotKeys()
        activationTracker.start()
        cleanupOldCaptures()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: SettingsStore.changedNotification,
            object: settings
        )

        showPermissionSetupIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotKeys()
        activationTracker.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "CursorShot")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "CursorShot"

        let menu = NSMenu()
        menu.addItem(menuItem(title: "Capture Now", symbolName: "viewfinder", action: #selector(captureNow)))
        menu.addItem(menuItem(title: "Settings", symbolName: "gearshape", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit", symbolName: "power", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func configureAppIcon() {
        NSApp.applicationIconImage = CursorShotIconProvider.image()
    }

    private func menuItem(
        title: String,
        symbolName: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        item.image = image
        return item
    }

    private func registerHotKeys() {
        register(
            manager: defaultCaptureHotKeyManager,
            hotKey: settings.defaultCaptureHotKey,
            role: .defaultCapture
        ) { [weak self] in
            self?.captureCoordinator?.captureNow()
        }
        register(
            manager: cmdTabQuickCaptureHotKeyManager,
            hotKey: settings.cmdTabQuickCaptureHotKey,
            role: .cmdTabQuickCapture
        ) { [weak self] in
            self?.captureCoordinator?.captureCmdTabImmediateScreenshot()
        }
        register(
            manager: currentSpaceQuickCaptureHotKeyManager,
            hotKey: settings.currentSpaceQuickCaptureHotKey,
            role: .currentSpaceQuickCapture
        ) { [weak self] in
            self?.captureCoordinator?.captureCurrentSpaceImmediateScreenshot()
        }
    }

    private func register(
        manager: HotKeyManager,
        hotKey: HotKey,
        role: HotKeyRole,
        handler: @escaping () -> Void
    ) {
        if let error = manager.register(hotKey, handler: handler) {
            DebugLog.write("hotkey registration failed role=\(role.rawValue) errorType=\(String(describing: type(of: error)))")
            errorPresenter.showError(error)
        }
    }

    private func unregisterHotKeys() {
        defaultCaptureHotKeyManager.unregister()
        cmdTabQuickCaptureHotKeyManager.unregister()
        currentSpaceQuickCaptureHotKeyManager.unregister()
    }

    private func cleanupOldCaptures() {
        do {
            let storage = CaptureStorage(
                directory: URL(fileURLWithPath: settings.effectiveStorageDirectory, isDirectory: true),
                protectsDirectoryPermissions: settings.usesManagedStorageDirectory
            )
            _ = try storage.cleanup(olderThanDays: settings.retentionDays)
        } catch {
            errorPresenter.showError(error)
        }
    }

    private func refreshActivationPolicy() {
        NSApp.setActivationPolicy(PermissionCenter.hasAllPermissions ? .accessory : .regular)
    }

    private func showPermissionSetupIfNeeded() {
        guard !PermissionCenter.hasAllPermissions else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !PermissionCenter.hasAllPermissions else {
                return
            }

            self.settingsWindowController?.show(reason: .permissions)
            PermissionGuideWindowController.startSystemPermissionFlow(
                preferredTarget: .accessibility,
                requestPrompts: true
            )
        }
    }

    @objc private func settingsChanged() {
        registerHotKeys()
    }

    @objc private func captureNow() {
        captureCoordinator?.captureNow()
    }

    @objc private func showSettings() {
        settingsWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
