import Foundation

public struct CaptureStorage {
    public static let legacyDefaultDirectoryPath = "/tmp/agent-shots"

    public static var defaultDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("CursorShot", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    public let directory: URL
    private let fileManager: FileManager
    private let protectsDirectoryPermissions: Bool

    public init(
        directory: URL = Self.defaultDirectory,
        fileManager: FileManager = .default,
        protectsDirectoryPermissions: Bool = true
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.protectsDirectoryPermissions = protectsDirectoryPermissions
    }

    public func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: directoryAttributes
        )

        if protectsDirectoryPermissions {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: directory.path
            )
        }
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
        for url in urls where Self.isCursorShotArtifact(url) {
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

    private var directoryAttributes: [FileAttributeKey: Any]? {
        guard protectsDirectoryPermissions else {
            return nil
        }

        return [.posixPermissions: NSNumber(value: Int16(0o700))]
    }

    private static func isCursorShotArtifact(_ url: URL) -> Bool {
        guard ["png", "json"].contains(url.pathExtension.lowercased()) else {
            return false
        }

        let stem = url.deletingPathExtension().lastPathComponent
        return UUID(uuidString: stem) != nil
    }
}
