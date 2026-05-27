import AppKit

enum CursorShotIconProvider {
    static func image() -> NSImage {
        if let resourceURL = Bundle.main.url(forResource: "CursorShot", withExtension: "icns"),
           let image = NSImage(contentsOf: resourceURL) {
            return image
        }

        if let image = NSImage(named: "CursorShot") ?? NSImage(named: "CursorShotIcon") {
            return image
        }

        let bundleIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
        if bundleIcon.isValid {
            return bundleIcon
        }

        return NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "CursorShot") ?? NSImage()
    }
}
