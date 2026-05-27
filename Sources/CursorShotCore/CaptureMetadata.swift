import CoreGraphics
import Foundation

public struct CaptureMetadata: Codable, Equatable {
    public let id: String
    public let imagePath: String
    public let width: Int
    public let height: Int
    public let selection: SelectionMetadata
    public let origin: OriginMetadata
    public let annotation: AnnotationSessionMetadata?
    public let createdAt: Date

    public init(artifact: CaptureArtifact) {
        id = artifact.id.uuidString
        imagePath = artifact.imageURL.path
        width = artifact.width
        height = artifact.height
        selection = SelectionMetadata(selection: artifact.selection)
        origin = OriginMetadata(origin: artifact.origin)
        annotation = artifact.annotation
        createdAt = artifact.origin.capturedAt
    }
}

public struct SelectionMetadata: Codable, Equatable {
    public let kind: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let windowID: UInt32?

    public init(selection: CaptureSelection) {
        let rect = selection.rect
        kind = selection.kind
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
        if case .window(_, let capturedWindowID) = selection {
            windowID = capturedWindowID
        } else {
            windowID = nil
        }
    }
}

public struct OriginMetadata: Codable, Equatable {
    public let pid: Int
    public let bundleId: String?
    public let appName: String?
    public let windowTitle: String?
    public let selectedRangeLocation: Int?
    public let selectedRangeLength: Int?
    public let mouseX: Double
    public let mouseY: Double
    public let capturedAt: Date

    public init(origin: OriginContext) {
        pid = Int(origin.pid)
        bundleId = origin.bundleId
        appName = origin.appName
        windowTitle = origin.windowTitle
        selectedRangeLocation = origin.selectedRange?.location
        selectedRangeLength = origin.selectedRange?.length
        mouseX = origin.mouseLocation.x
        mouseY = origin.mouseLocation.y
        capturedAt = origin.capturedAt
    }
}

public struct CaptureMetadataWriter {
    private let encoder: JSONEncoder

    public init(encoder: JSONEncoder = JSONEncoder()) {
        self.encoder = encoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func write(_ metadata: CaptureMetadata, to url: URL) throws {
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}
