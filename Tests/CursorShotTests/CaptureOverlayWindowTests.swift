import AppKit
@testable import CursorShot
import XCTest

@MainActor
final class CaptureOverlayWindowTests: XCTestCase {
    func testOverlayWindowCanAppearOverFullScreenSpacesWithoutActivatingApp() throws {
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
