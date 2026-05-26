import Foundation

public struct ShellPathFormatter {
    public init() {}

    public func format(_ path: String) -> String {
        let safeCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+-./:")
        if path.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return path
        }

        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct MarkdownPathFormatter {
    public init() {}

    public func imageReference(path: String, altText: String = "screenshot") -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ")", with: "\\)")
        return "![\(altText)](\(escaped))"
    }
}
