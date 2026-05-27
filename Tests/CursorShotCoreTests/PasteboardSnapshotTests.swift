import AppKit
import CursorShotCore
import XCTest

final class PasteboardSnapshotTests: XCTestCase {
    func testRestoresStringPasteboardContent() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cursorShotTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("replacement", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testCapturesEmptyPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cursorShotTests-\(UUID().uuidString)"))
        pasteboard.clearContents()

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        XCTAssertEqual(snapshot.items, [])
    }
}
