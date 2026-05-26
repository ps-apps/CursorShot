import ApplicationServices
import CoreGraphics
import Foundation

public struct OriginContext {
    public let pid: pid_t
    public let bundleId: String?
    public let appName: String?
    public let windowTitle: String?
    public let focusedElement: AXUIElement?
    public let selectedRange: CFRange?
    public let mouseLocation: CGPoint
    public let capturedAt: Date

    public init(
        pid: pid_t,
        bundleId: String?,
        appName: String?,
        windowTitle: String?,
        focusedElement: AXUIElement?,
        selectedRange: CFRange?,
        mouseLocation: CGPoint,
        capturedAt: Date
    ) {
        self.pid = pid
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.focusedElement = focusedElement
        self.selectedRange = selectedRange
        self.mouseLocation = mouseLocation
        self.capturedAt = capturedAt
    }
}

public struct CaptureArtifact {
    public let id: UUID
    public let imageURL: URL
    public let metadataURL: URL
    public let width: Int
    public let height: Int
    public let origin: OriginContext
    public let selection: CaptureSelection
    public let annotation: AnnotationSessionMetadata?

    public init(
        id: UUID,
        imageURL: URL,
        metadataURL: URL,
        width: Int,
        height: Int,
        origin: OriginContext,
        selection: CaptureSelection,
        annotation: AnnotationSessionMetadata? = nil
    ) {
        self.id = id
        self.imageURL = imageURL
        self.metadataURL = metadataURL
        self.width = width
        self.height = height
        self.origin = origin
        self.selection = selection
        self.annotation = annotation
    }
}

public enum CaptureSelection: Equatable {
    case region(CGRect)
    case window(CGRect, windowID: CGWindowID? = nil)
    case display(CGRect)

    public var rect: CGRect {
        switch self {
        case .region(let rect), .window(let rect, _), .display(let rect):
            rect
        }
    }

    public var kind: String {
        switch self {
        case .region:
            "region"
        case .window:
            "window"
        case .display:
            "display"
        }
    }
}

public enum TargetProfile: String, Codable, Equatable, CaseIterable {
    case terminal
    case markdownText
    case plainText
    case richPaste
    case unknown
}

public enum InjectionMode: String, Codable, Equatable, CaseIterable {
    case smart
    case alwaysPath
    case alwaysImage
}

public enum InjectionPayload: Equatable {
    case text(String)
    case image(URL, fallbackText: String)

    public var fallbackText: String {
        switch self {
        case .text(let text):
            text
        case .image(_, let fallbackText):
            fallbackText
        }
    }
}
