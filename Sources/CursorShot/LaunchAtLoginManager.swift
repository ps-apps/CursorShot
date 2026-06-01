import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so CursorShot can register itself as a login item
/// and auto-start on login/restart. Requires a properly located, signed build;
/// registration is a harmless no-op failure for unsigned `swift run` dev builds.
@MainActor
enum LaunchAtLoginManager {
    /// Whether the app is currently registered to open at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the login item, returning the resulting enabled state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            DebugLog.write("launch-at-login update failed enabled=\(enabled) status=\(service.status.rawValue) error=\(error.localizedDescription)")
        }
        return isEnabled
    }
}
