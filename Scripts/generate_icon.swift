import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "CursorShot.icns")
let fileManager = FileManager.default
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("cursorShotIcon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = temporaryDirectory.appendingPathComponent("CursorShot.iconset", isDirectory: true)

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for size in sizes {
    let image = NSImage(size: NSSize(width: size.pixels, height: size.pixels))
    image.lockFocus()

    let scale = CGFloat(size.pixels)
    let rect = NSRect(x: 0, y: 0, width: size.pixels, height: size.pixels)
    let shell = NSBezierPath(
        roundedRect: rect.insetBy(dx: scale * 0.055, dy: scale * 0.055),
        xRadius: scale * 0.20,
        yRadius: scale * 0.20
    )
    shell.addClip()

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.38, blue: 0.36, alpha: 1)
    ])
    background?.draw(in: rect, angle: 38)

    NSColor.white.withAlphaComponent(0.16).setStroke()
    shell.lineWidth = max(1, scale * 0.018)
    shell.stroke()

    let ringRect = rect.insetBy(dx: scale * 0.22, dy: scale * 0.22)
    NSColor(calibratedRed: 0.45, green: 0.95, blue: 0.72, alpha: 1).setStroke()
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = max(2, scale * 0.052)
    ring.stroke()

    NSColor(calibratedRed: 0.26, green: 0.58, blue: 1.0, alpha: 1).setStroke()
    let focus = NSBezierPath(ovalIn: ringRect.insetBy(dx: scale * 0.12, dy: scale * 0.12))
    focus.lineWidth = max(1.5, scale * 0.025)
    focus.stroke()

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: scale * 0.36, y: scale * 0.72))
    cursor.line(to: NSPoint(x: scale * 0.36, y: scale * 0.25))
    cursor.line(to: NSPoint(x: scale * 0.49, y: scale * 0.38))
    cursor.line(to: NSPoint(x: scale * 0.57, y: scale * 0.20))
    cursor.line(to: NSPoint(x: scale * 0.66, y: scale * 0.25))
    cursor.line(to: NSPoint(x: scale * 0.58, y: scale * 0.43))
    cursor.line(to: NSPoint(x: scale * 0.75, y: scale * 0.43))
    cursor.close()
    NSColor.white.setFill()
    cursor.fill()
    NSColor.black.withAlphaComponent(0.22).setStroke()
    cursor.lineWidth = max(1, scale * 0.018)
    cursor.stroke()

    NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 1).setFill()
    let dotSize = scale * 0.085
    NSBezierPath(
        ovalIn: NSRect(x: scale * 0.64, y: scale * 0.63, width: dotSize, height: dotSize)
    ).fill()

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "cursorShotIcon", code: 1)
    }

    try png.write(to: iconsetURL.appendingPathComponent(size.name), options: [.atomic])
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "cursorShotIcon", code: Int(process.terminationStatus))
}

try? fileManager.removeItem(at: temporaryDirectory)
