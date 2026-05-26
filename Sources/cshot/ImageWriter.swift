import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageWriterError: LocalizedError {
    case destinationCreationFailed(URL)
    case finalizeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .destinationCreationFailed(let url):
            "Could not create image destination at \(url.path)."
        case .finalizeFailed(let url):
            "Could not write PNG image at \(url.path)."
        }
    }
}

struct ImageWriter {
    func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageWriterError.destinationCreationFailed(url)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageWriterError.finalizeFailed(url)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}
