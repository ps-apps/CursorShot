import CoreGraphics
import CursorShotCore
import XCTest

final class CaptureMetadataTests: XCTestCase {
    func testMetadataEncodesArtifactDetails() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let imageURL = URL(fileURLWithPath: "/tmp/agent-shots/\(id.uuidString).png")
        let origin = OriginContext(
            pid: 42,
            bundleId: "com.microsoft.VSCode",
            appName: "Code",
            windowTitle: "main.swift",
            focusedElement: nil,
            selectedRange: CFRange(location: 7, length: 3),
            mouseLocation: CGPoint(x: 10, y: 20),
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let artifact = CaptureArtifact(
            id: id,
            imageURL: imageURL,
            metadataURL: imageURL.deletingPathExtension().appendingPathExtension("json"),
            width: 640,
            height: 480,
            origin: origin,
            selection: .window(CGRect(x: 1, y: 2, width: 3, height: 4), windowID: 99)
        )

        let metadata = CaptureMetadata(artifact: artifact)

        XCTAssertEqual(metadata.id, id.uuidString)
        XCTAssertEqual(metadata.imagePath, imageURL.path)
        XCTAssertEqual(metadata.selection.kind, "window")
        XCTAssertEqual(metadata.selection.x, 1)
        XCTAssertEqual(metadata.selection.windowID, 99)
        XCTAssertEqual(metadata.origin.pid, 42)
        XCTAssertEqual(metadata.origin.bundleId, "com.microsoft.VSCode")
        XCTAssertEqual(metadata.origin.selectedRangeLocation, 7)
        XCTAssertEqual(metadata.origin.selectedRangeLength, 3)
    }

    func testMetadataWriterWritesJson() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursorShotMetadataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("metadata.json")
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let imageURL = directory.appendingPathComponent("image.png")
        let origin = OriginContext(
            pid: 1,
            bundleId: nil,
            appName: nil,
            windowTitle: nil,
            focusedElement: nil,
            selectedRange: nil,
            mouseLocation: .zero,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        let artifact = CaptureArtifact(
            id: id,
            imageURL: imageURL,
            metadataURL: url,
            width: 1,
            height: 1,
            origin: origin,
            selection: .display(CGRect(x: 0, y: 0, width: 1, height: 1))
        )

        try CaptureMetadataWriter().write(CaptureMetadata(artifact: artifact), to: url)

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder.cursorShot.decode(CaptureMetadata.self, from: data)
        XCTAssertEqual(decoded.id, id.uuidString)
        XCTAssertEqual(decoded.selection.kind, "display")
    }
}

private extension JSONDecoder {
    static var cursorShot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
