import CursorShotCore
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
        let directory = temporaryDirectory()
        let urls = CaptureStorage(directory: directory).urls(for: id)

        XCTAssertEqual(urls.image.path, directory.appendingPathComponent("\(id.uuidString).png").path)
        XCTAssertEqual(urls.metadata.path, directory.appendingPathComponent("\(id.uuidString).json").path)
    }

    func testCleanupRemovesOldCursorShotArtifactsOnly() throws {
        let directory = temporaryDirectory()
        let storage = CaptureStorage(directory: directory)
        try storage.prepareDirectory()

        let oldID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let oldUrls = storage.urls(for: oldID)
        let unrelatedOldPng = directory.appendingPathComponent("old.png")
        let unrelatedOldJson = directory.appendingPathComponent("old.json")
        let oldTxt = directory.appendingPathComponent("old.txt")
        let freshUrls = storage.urls(for: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!)

        try Data("old".utf8).write(to: oldUrls.image)
        try Data("old".utf8).write(to: oldUrls.metadata)
        try Data("old".utf8).write(to: unrelatedOldPng)
        try Data("old".utf8).write(to: unrelatedOldJson)
        try Data("old".utf8).write(to: oldTxt)
        try Data("fresh".utf8).write(to: freshUrls.image)

        let now = Date(timeIntervalSince1970: 10_000)
        let oldDate = now.addingTimeInterval(-3 * 24 * 60 * 60)
        try [oldUrls.image, oldUrls.metadata, unrelatedOldPng, unrelatedOldJson, oldTxt].forEach { url in
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        }

        let removed = try storage.cleanup(olderThanDays: 1, now: now)

        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), [oldUrls.image.lastPathComponent, oldUrls.metadata.lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldUrls.image.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldUrls.metadata.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedOldPng.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedOldJson.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldTxt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshUrls.image.path))
    }

    func testPrepareDirectoryDoesNotChmodCustomDirectoryWhenProtectionDisabled() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o755))]
        )
        let storage = CaptureStorage(directory: directory, protectsDirectoryPermissions: false)

        try storage.prepareDirectory()

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o755)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cursorShotTests-\(UUID().uuidString)", isDirectory: true)
    }
}
