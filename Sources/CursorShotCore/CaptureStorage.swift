import Foundation

public struct CaptureStorage {
    public let directory: URL
    private let fileManager: FileManager

    public init(
        directory: URL = URL(fileURLWithPath: "/tmp/agent-shots", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )
    }

    public func urls(for id: UUID) -> (image: URL, metadata: URL) {
        (
            image: directory.appendingPathComponent("\(id.uuidString).png"),
            metadata: directory.appendingPathComponent("\(id.uuidString).json")
        )
    }

    @discardableResult
    public func cleanup(olderThanDays days: Int, now: Date = Date()) throws -> [URL] {
        guard days >= 0 else {
            return []
        }

        try prepareDirectory()
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var removed: [URL] = []
        for url in urls where ["png", "json"].contains(url.pathExtension.lowercased()) {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, let modifiedAt = values.contentModificationDate else {
                continue
            }

            if modifiedAt < cutoff {
                try fileManager.removeItem(at: url)
                removed.append(url)
            }
        }

        return removed
    }
}
