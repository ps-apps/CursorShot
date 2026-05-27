import CursorShotCore
import XCTest

final class TargetProfileClassifierTests: XCTestCase {
    private let classifier = TargetProfileClassifier()

    func testClassifiesTerminalApps() {
        XCTAssertEqual(classifier.classify(bundleId: "com.apple.Terminal", appName: "Terminal"), .terminal)
        XCTAssertEqual(classifier.classify(bundleId: "com.googlecode.iterm2", appName: "iTerm2"), .terminal)
        XCTAssertEqual(classifier.classify(bundleId: "dev.warp.Warp-Stable", appName: "Warp"), .terminal)
        XCTAssertEqual(classifier.classify(bundleId: "com.mitchellh.ghostty", appName: "Ghostty"), .terminal)
    }

    func testClassifiesEditorAppsAsMarkdownText() {
        XCTAssertEqual(classifier.classify(bundleId: "com.microsoft.VSCode", appName: "Code"), .markdownText)
        XCTAssertEqual(classifier.classify(bundleId: "com.todesktop.230313mzl4w4u92", appName: "Cursor"), .markdownText)
        XCTAssertEqual(classifier.classify(bundleId: "dev.zed.Zed", appName: "Zed"), .markdownText)
        XCTAssertEqual(classifier.classify(bundleId: "com.jetbrains.intellij", appName: "IntelliJ IDEA"), .markdownText)
    }

    func testClassifiesRichPasteApps() {
        XCTAssertEqual(classifier.classify(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack"), .richPaste)
        XCTAssertEqual(classifier.classify(bundleId: "com.hnc.Discord", appName: "Discord"), .richPaste)
        XCTAssertEqual(classifier.classify(bundleId: "com.google.Chrome", appName: "Chrome"), .richPaste)
        XCTAssertEqual(classifier.classify(bundleId: "company.thebrowser.Browser", appName: "Arc"), .richPaste)
    }

    func testFallsBackToNameWhenBundleIdIsMissing() {
        XCTAssertEqual(classifier.classify(bundleId: nil, appName: "Warp"), .terminal)
        XCTAssertEqual(classifier.classify(bundleId: nil, appName: "Cursor"), .markdownText)
        XCTAssertEqual(classifier.classify(bundleId: nil, appName: "Slack"), .richPaste)
    }

    func testUnknownWhenNoSignalsMatch() {
        XCTAssertEqual(classifier.classify(bundleId: "example.unknown", appName: "Unknown"), .unknown)
    }
}
