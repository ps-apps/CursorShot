import CoreGraphics
import CursorShotCore
import XCTest

final class InjectionPayloadFactoryTests: XCTestCase {
    private let factory = InjectionPayloadFactory()

    func testTerminalPayloadUsesShellSafePath() {
        let artifact = makeArtifact(path: "/tmp/agent-shots/test image.png")

        XCTAssertEqual(
            factory.payload(for: artifact, targetProfile: .terminal, mode: .smart),
            .text("'/tmp/agent-shots/test image.png'")
        )
    }

    func testMarkdownPayloadPrefersImageWithPathFallback() {
        let artifact = makeArtifact(path: "/tmp/agent-shots/test.png")

        XCTAssertEqual(
            factory.payload(for: artifact, targetProfile: .markdownText, mode: .smart),
            .image(URL(fileURLWithPath: "/tmp/agent-shots/test.png"), fallbackText: "Screenshot: /tmp/agent-shots/test.png")
        )
    }

    func testPlainTextPayloadPrefersImageWithPathFallback() {
        let artifact = makeArtifact(path: "/tmp/agent-shots/test.png")

        XCTAssertEqual(
            factory.payload(for: artifact, targetProfile: .plainText, mode: .smart),
            .image(URL(fileURLWithPath: "/tmp/agent-shots/test.png"), fallbackText: "Screenshot: /tmp/agent-shots/test.png")
        )
    }

    func testRichPastePayloadUsesImageWithFallback() {
        let artifact = makeArtifact(path: "/tmp/agent-shots/test.png")

        XCTAssertEqual(
            factory.payload(for: artifact, targetProfile: .richPaste, mode: .smart),
            .image(URL(fileURLWithPath: "/tmp/agent-shots/test.png"), fallbackText: "Screenshot: /tmp/agent-shots/test.png")
        )
    }

    func testAlwaysPathOverridesTargetProfile() {
        let artifact = makeArtifact(path: "/tmp/agent-shots/test.png")

        XCTAssertEqual(
            factory.payload(for: artifact, targetProfile: .richPaste, mode: .alwaysPath),
            .text("/tmp/agent-shots/test.png")
        )
    }

    func testAlwaysImageOverridesTargetProfile() {
        let artifact = makeArtifact(path: "/tmp/agent-shots/test.png")

        XCTAssertEqual(
            factory.payload(for: artifact, targetProfile: .terminal, mode: .alwaysImage),
            .image(URL(fileURLWithPath: "/tmp/agent-shots/test.png"), fallbackText: "Screenshot: /tmp/agent-shots/test.png")
        )
    }

    private func makeArtifact(path: String) -> CaptureArtifact {
        let imageURL = URL(fileURLWithPath: path)
        let origin = OriginContext(
            pid: 123,
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            windowTitle: "Terminal",
            focusedElement: nil,
            selectedRange: nil,
            mouseLocation: .zero,
            capturedAt: Date(timeIntervalSince1970: 1)
        )

        return CaptureArtifact(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            imageURL: imageURL,
            metadataURL: imageURL.deletingPathExtension().appendingPathExtension("json"),
            width: 100,
            height: 80,
            origin: origin,
            selection: .region(CGRect(x: 1, y: 2, width: 100, height: 80))
        )
    }
}
