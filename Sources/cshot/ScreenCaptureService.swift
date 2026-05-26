import AppKit
import CoreGraphics
import cshotCore
import ScreenCaptureKit

enum ScreenCaptureServiceError: LocalizedError {
    case emptySelection
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "The selected screenshot area is empty."
        case .captureFailed(let message):
            "Screenshot capture failed: \(message)"
        }
    }
}

@MainActor
final class ScreenCaptureService {
    private let converter = CoordinateConverter()

    func capture(selection: CaptureSelection) async throws -> CGImage {
        let rect = selection.rect.integral
        guard rect.width > 0, rect.height > 0 else {
            throw ScreenCaptureServiceError.emptySelection
        }

        if case .window(_, let windowID?) = selection {
            return try captureWindow(windowID: windowID)
        }

        let captureRect = converter.quartzRect(
            fromAppKitRect: rect,
            screenFrames: NSScreen.screens.map(\.frame)
        ).integral

        if #available(macOS 15.2, *) {
            do {
                return try await captureWithScreenCaptureKit(rect: captureRect)
            } catch {
                return try captureWithCoreGraphics(rect: captureRect)
            }
        }

        return try captureWithCoreGraphics(rect: captureRect)
    }

    private func captureWindow(windowID: CGWindowID) throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw ScreenCaptureServiceError.captureFailed("CoreGraphics returned no image for selected window.")
        }

        return image
    }

    @available(macOS 15.2, *)
    private func captureWithScreenCaptureKit(rect: CGRect) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: rect) { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                continuation.resume(
                    throwing: error ?? ScreenCaptureServiceError.captureFailed("ScreenCaptureKit returned no image.")
                )
            }
        }
    }

    private func captureWithCoreGraphics(rect: CGRect) throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw ScreenCaptureServiceError.captureFailed("CoreGraphics returned no image.")
        }

        return image
    }
}
