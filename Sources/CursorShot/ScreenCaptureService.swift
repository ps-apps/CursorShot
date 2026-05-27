import AppKit
import CoreGraphics
import CursorShotCore
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
            return try await captureWindow(windowID: windowID)
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

    private func captureWindow(windowID: CGWindowID) async throws -> CGImage {
        if let image = captureWindowWithCoreGraphics(windowID: windowID) {
            DebugLog.write("CoreGraphics window capture windowID=\(windowID) width=\(image.width) height=\(image.height)")
            return image
        }

        if #available(macOS 14.0, *) {
            do {
                return try await captureWindowWithScreenCaptureKit(windowID: windowID)
            } catch {
                DebugLog.write("ScreenCaptureKit window capture failed windowID=\(windowID) errorType=\(String(describing: type(of: error)))")
            }
        }

        throw ScreenCaptureServiceError.captureFailed("CoreGraphics returned no image for selected window.")
    }

    private func captureWindowWithCoreGraphics(windowID: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    @available(macOS 14.0, *)
    private func captureWindowWithScreenCaptureKit(windowID: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: false
        )
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureServiceError.captureFailed("ScreenCaptureKit could not find window \(windowID).")
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.ignoreShadowsSingleWindow = true

        DebugLog.write("ScreenCaptureKit window capture windowID=\(windowID) frame=\(window.frame) scale=\(scale) output=\(configuration.width)x\(configuration.height)")

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                continuation.resume(
                    throwing: error ?? ScreenCaptureServiceError.captureFailed("ScreenCaptureKit returned no image for window \(windowID).")
                )
            }
        }
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
