import Foundation

enum DebugLog {
    private static let queue = DispatchQueue(label: "CursorShot.debug-log")
    private static let maximumLogSize = 512 * 1024
    static let url: URL = {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("CursorShot", isDirectory: true)
            .appendingPathComponent("CursorShot.log")
    }()

    static func write(_ message: String, fileID: String = #fileID, line: Int = #line) {
        let fileID = fileID
        let line = line
        let message = sanitized(message)
        queue.async {
            prepareLogFileIfNeeded()
            rotateIfNeeded()

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let text = "\(timestamp) [\(fileID):\(line)] \(message)\n"
            let data = Data(text.utf8)

            guard let handle = try? FileHandle(forWritingTo: url) else {
                return
            }

            defer {
                try? handle.close()
            }

            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
    }

    private static func prepareLogFileIfNeeded() {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )

        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
            )
        }
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    private static func rotateIfNeeded() {
        let fileManager = FileManager.default
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber,
            size.intValue > maximumLogSize
        else {
            return
        }

        let rotatedURL = url.deletingPathExtension().appendingPathExtension("log.1")
        try? fileManager.removeItem(at: rotatedURL)
        try? fileManager.moveItem(at: url, to: rotatedURL)
        fileManager.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
        )
    }

    private static func sanitized(_ message: String) -> String {
        var output = message
        let sensitivePatterns = [
            #"(title|path|bundle|app|owner|image|metadata|url|message)=([^,\s}\)]+)"#,
            #"(title|path|bundle|app|owner|image|metadata|url|message)='[^']*'"#,
            #"(mouse)=\([^\)]*\)"#,
            #"(selectedRange)=([^,\s}\)]+)"#
        ]

        for pattern in sensitivePatterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "$1=<redacted>",
                options: .regularExpression
            )
        }

        return output
    }
}
