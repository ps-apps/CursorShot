import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "cshot.icns")
let fileManager = FileManager.default
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("cshotIcon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = temporaryDirectory.appendingPathComponent("cshot.iconset", isDirectory: true)

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

    let rect = NSRect(x: 0, y: 0, width: size.pixels, height: size.pixels)
    NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size.pixels) * 0.06, dy: CGFloat(size.pixels) * 0.06), xRadius: CGFloat(size.pixels) * 0.18, yRadius: CGFloat(size.pixels) * 0.18).fill()

    let apertureRect = rect.insetBy(dx: CGFloat(size.pixels) * 0.2, dy: CGFloat(size.pixels) * 0.2)
    NSColor(calibratedRed: 0.18, green: 0.56, blue: 1.0, alpha: 1).setStroke()
    let aperture = NSBezierPath(roundedRect: apertureRect, xRadius: CGFloat(size.pixels) * 0.09, yRadius: CGFloat(size.pixels) * 0.09)
    aperture.lineWidth = max(2, CGFloat(size.pixels) * 0.055)
    aperture.stroke()

    NSColor(calibratedRed: 0.50, green: 0.95, blue: 0.72, alpha: 1).setFill()
    let dotSize = CGFloat(size.pixels) * 0.12
    NSBezierPath(ovalIn: NSRect(x: rect.midX - dotSize / 2, y: rect.midY - dotSize / 2, width: dotSize, height: dotSize)).fill()

    NSColor.white.withAlphaComponent(0.82).setStroke()
    let crosshair = NSBezierPath()
    crosshair.lineWidth = max(1, CGFloat(size.pixels) * 0.024)
    crosshair.move(to: NSPoint(x: rect.midX, y: apertureRect.minY + CGFloat(size.pixels) * 0.04))
    crosshair.line(to: NSPoint(x: rect.midX, y: apertureRect.minY + CGFloat(size.pixels) * 0.18))
    crosshair.move(to: NSPoint(x: rect.midX, y: apertureRect.maxY - CGFloat(size.pixels) * 0.04))
    crosshair.line(to: NSPoint(x: rect.midX, y: apertureRect.maxY - CGFloat(size.pixels) * 0.18))
    crosshair.move(to: NSPoint(x: apertureRect.minX + CGFloat(size.pixels) * 0.04, y: rect.midY))
    crosshair.line(to: NSPoint(x: apertureRect.minX + CGFloat(size.pixels) * 0.18, y: rect.midY))
    crosshair.move(to: NSPoint(x: apertureRect.maxX - CGFloat(size.pixels) * 0.04, y: rect.midY))
    crosshair.line(to: NSPoint(x: apertureRect.maxX - CGFloat(size.pixels) * 0.18, y: rect.midY))
    crosshair.stroke()

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "cshotIcon", code: 1)
    }

    try png.write(to: iconsetURL.appendingPathComponent(size.name), options: [.atomic])
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "cshotIcon", code: Int(process.terminationStatus))
}

try? fileManager.removeItem(at: temporaryDirectory)
