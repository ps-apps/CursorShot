import AppKit
import cshotCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let hotKeyManager = HotKeyManager()
    private let errorPresenter = ErrorPresenter()

    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var captureCoordinator: CaptureCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshActivationPolicy()

        settingsWindowController = SettingsWindowController(settings: settings)
        captureCoordinator = CaptureCoordinator(settings: settings, errorPresenter: errorPresenter)

        configureAppIcon()
        configureStatusItem()
        registerHotKey()
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
        hotKeyManager.unregister()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "cshot")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "cshot"

        let menu = NSMenu()
        menu.addItem(menuItem(title: "Capture Now", symbolName: "viewfinder", action: #selector(captureNow)))
        menu.addItem(menuItem(title: "Settings", symbolName: "gearshape", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit", symbolName: "power", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func configureAppIcon() {
        if let icon = NSImage(named: "cshot") ?? NSImage(named: "cshotIcon") {
            NSApp.applicationIconImage = icon
            return
        }

        NSApp.applicationIconImage = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "cshot")
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

    private func registerHotKey() {
        hotKeyManager.register(settings.hotKey) { [weak self] in
            self?.captureCoordinator?.captureNow()
        }
    }

    private func cleanupOldCaptures() {
        do {
            let storage = CaptureStorage(
                directory: URL(fileURLWithPath: settings.effectiveStorageDirectory, isDirectory: true)
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
            PermissionGuideWindowController.shared.show(preferredTarget: .accessibility, requestPrompts: true)
        }
    }

    @objc private func settingsChanged() {
        registerHotKey()
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
