import cshotCore
import XCTest

final class CaptureStorageTests: XCTestCase {
    func testPrepareDirectoryCreatesPrivateDirectory() throws {
        let directory = temporaryDirectory()
        let storage = CaptureStorage(directory: directory)

        try storage.prepareDirectory()

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
    }

    func testUrlsUseSharedUuidStem() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let directory = URL(fileURLWithPath: "/tmp/agent-shots", isDirectory: true)
        let urls = CaptureStorage(directory: directory).urls(for: id)

        XCTAssertEqual(urls.image.path, "/tmp/agent-shots/\(id.uuidString).png")
        XCTAssertEqual(urls.metadata.path, "/tmp/agent-shots/\(id.uuidString).json")
    }

    func testCleanupRemovesOldPngAndJsonOnly() throws {
        let directory = temporaryDirectory()
        let storage = CaptureStorage(directory: directory)
        try storage.prepareDirectory()

        let oldPng = directory.appendingPathComponent("old.png")
        let oldJson = directory.appendingPathComponent("old.json")
        let oldTxt = directory.appendingPathComponent("old.txt")
        let freshPng = directory.appendingPathComponent("fresh.png")

        try Data("old".utf8).write(to: oldPng)
        try Data("old".utf8).write(to: oldJson)
        try Data("old".utf8).write(to: oldTxt)
        try Data("fresh".utf8).write(to: freshPng)

        let now = Date(timeIntervalSince1970: 10_000)
        let oldDate = now.addingTimeInterval(-3 * 24 * 60 * 60)
        try [oldPng, oldJson, oldTxt].forEach { url in
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        }

        let removed = try storage.cleanup(olderThanDays: 1, now: now)

        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), ["old.png", "old.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPng.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldJson.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldTxt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshPng.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cshotTests-\(UUID().uuidString)", isDirectory: true)
    }
}
