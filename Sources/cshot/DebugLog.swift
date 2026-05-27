import Foundation

enum DebugLog {
    private static let queue = DispatchQueue(label: "cshot.debug-log")
    static let url = URL(fileURLWithPath: "/tmp/cshot-debug.log")

    static func write(_ message: String, fileID: String = #fileID, line: Int = #line) {
        let fileID = fileID
        let line = line
        let message = message
        queue.async {
            let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
            let text = "\(timestamp) [\(fileID):\(line)] \(message)\n"
            let data = Data(text.utf8)

            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

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
}
