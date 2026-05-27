import AppKit
@testable import CursorShot
import XCTest

@MainActor
final class CaptureOverlayWindowTests: XCTestCase {
    func testSettingsWindowKeepsCursorShotOutOfTheDock() throws {
        let app = NSApplication.shared
        let originalActivationPolicy = app.activationPolicy()
        defer {
            app.setActivationPolicy(originalActivationPolicy)
        }

        app.setActivationPolicy(.accessory)
        let suiteName = "CursorShotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            app.windows
                .filter { $0.title == "CursorShot Settings" }
                .forEach { $0.close() }
        }

        let controller = SettingsWindowController(settings: SettingsStore(defaults: defaults))
        controller.show()

        XCTAssertEqual(app.activationPolicy(), .accessory)
    }

    func testOverlayWindowIsConfiguredToAppearOverFullScreenSpacesWithoutActivatingApp() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("Capture overlay window tests require at least one screen.")
        }

        let controller = CaptureOverlayController { _ in }
        let window = CaptureOverlayWindow(screen: screen, controller: controller)
        defer {
            window.close()
        }
        let panel: NSPanel = window

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertEqual(panel.level, .screenSaver)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }
}
