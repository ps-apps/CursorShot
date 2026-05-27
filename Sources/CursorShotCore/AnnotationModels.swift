import CoreGraphics
import Foundation

public enum AnnotationTool: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case arrow
    case line
    case rectangle
    case oval
    case highlight
    case text
    case blur
    case crop
}

public enum AnnotationSessionMode: String, Codable, Equatable, Sendable {
    case annotated
    case discarded
}

public enum AnnotationRedactionStyle: String, Codable, Equatable, Sendable {
    case blur
}

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = Self.clamped(x)
        self.y = Self.clamped(y)
    }

    public init(pixelPoint: CGPoint, imageSize: CGSize) {
        let width = max(Double(imageSize.width), 1)
        let height = max(Double(imageSize.height), 1)
        self.init(
            x: Double(pixelPoint.x) / width,
            y: Double(pixelPoint.y) / height
        )
    }

    public func pixelPoint(in imageSize: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(x) * imageSize.width,
            y: CGFloat(y) * imageSize.height
        )
    }

    public func translatedBy(pixelDelta: CGPoint, imageSize: CGSize) -> NormalizedPoint {
        NormalizedPoint(
            x: x + Double(pixelDelta.x / max(imageSize.width, 1)),
            y: y + Double(pixelDelta.y / max(imageSize.height, 1))
        )
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct NormalizedRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        let normalizedX = min(max(x, 0), 1)
        let normalizedY = min(max(y, 0), 1)
        let maxWidth = max(0, 1 - normalizedX)
        let maxHeight = max(0, 1 - normalizedY)

        self.x = normalizedX
        self.y = normalizedY
        self.width = min(max(width, 0), maxWidth)
        self.height = min(max(height, 0), maxHeight)
    }

    public init(pixelRect: CGRect, imageSize: CGSize) {
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        let standardized = pixelRect.standardized
        let bounded = standardized.intersection(CGRect(origin: .zero, size: imageSize))

        guard !bounded.isNull, !bounded.isEmpty else {
            self.init(x: 0, y: 0, width: 0, height: 0)
            return
        }

        self.init(
            x: Double(bounded.minX / width),
            y: Double(bounded.minY / height),
            width: Double(bounded.width / width),
            height: Double(bounded.height / height)
        )
    }

    public static func fromPoints(_ start: CGPoint, _ end: CGPoint, imageSize: CGSize) -> NormalizedRect {
        NormalizedRect(
            pixelRect: CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ),
            imageSize: imageSize
        )
    }

    public func pixelRect(in imageSize: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(x) * imageSize.width,
            y: CGFloat(y) * imageSize.height,
            width: CGFloat(width) * imageSize.width,
            height: CGFloat(height) * imageSize.height
        )
    }

    public func translatedBy(pixelDelta: CGPoint, imageSize: CGSize) -> NormalizedRect {
        let normalizedDeltaX = Double(pixelDelta.x / max(imageSize.width, 1))
        let normalizedDeltaY = Double(pixelDelta.y / max(imageSize.height, 1))
        let maxX = max(0, 1 - width)
        let maxY = max(0, 1 - height)

        return NormalizedRect(
            x: min(max(x + normalizedDeltaX, 0), maxX),
            y: min(max(y + normalizedDeltaY, 0), maxY),
            width: width,
            height: height
        )
    }
}

public struct AnnotationElement: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let tool: AnnotationTool
    public let start: NormalizedPoint?
    public let end: NormalizedPoint?
    public let rect: NormalizedRect?
    public let text: String?
    public let colorHex: String
    public let fillColorHex: String?
    public let strokeWidth: Double
    public let opacity: Double?
    public let fontSize: Double?
    public let fontName: String?

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        start: NormalizedPoint? = nil,
        end: NormalizedPoint? = nil,
        rect: NormalizedRect? = nil,
        text: String? = nil,
        colorHex: String,
        fillColorHex: String? = nil,
        strokeWidth: Double,
        opacity: Double? = nil,
        fontSize: Double? = nil,
        fontName: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.rect = rect
        self.text = text
        self.colorHex = colorHex
        self.fillColorHex = fillColorHex
        self.strokeWidth = max(1, strokeWidth)
        self.opacity = opacity.map { min(max($0, 0.05), 1) }
        self.fontSize = fontSize.map { min(max($0, 10), 96) }
        self.fontName = fontName
    }

    public static func arrow(
        id: UUID = UUID(),
        start: NormalizedPoint,
        end: NormalizedPoint,
        colorHex: String,
        strokeWidth: Double,
        opacity: Double = 1
    ) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: .arrow,
            start: start,
            end: end,
            colorHex: colorHex,
            strokeWidth: strokeWidth,
            opacity: opacity
        )
    }

    public static func line(
        id: UUID = UUID(),
        start: NormalizedPoint,
        end: NormalizedPoint,
        colorHex: String,
        strokeWidth: Double,
        opacity: Double = 1
    ) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: .line,
            start: start,
            end: end,
            colorHex: colorHex,
            strokeWidth: strokeWidth,
            opacity: opacity
        )
    }

    public static func rectangle(
        id: UUID = UUID(),
        rect: NormalizedRect,
        colorHex: String,
        strokeWidth: Double,
        fillColorHex: String? = nil,
        opacity: Double = 1
    ) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: .rectangle,
            rect: rect,
            colorHex: colorHex,
            fillColorHex: fillColorHex,
            strokeWidth: strokeWidth,
            opacity: opacity
        )
    }

    public static func oval(
        id: UUID = UUID(),
        rect: NormalizedRect,
        colorHex: String,
        strokeWidth: Double,
        fillColorHex: String? = nil,
        opacity: Double = 1
    ) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: .oval,
            rect: rect,
            colorHex: colorHex,
            fillColorHex: fillColorHex,
            strokeWidth: strokeWidth,
            opacity: opacity
        )
    }

    public static func highlight(
        id: UUID = UUID(),
        rect: NormalizedRect,
        colorHex: String = "#FFD60A",
        opacity: Double = 0.35
    ) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: .highlight,
            rect: rect,
            colorHex: colorHex,
            strokeWidth: 1,
            opacity: opacity
        )
    }

    public static func text(
        id: UUID = UUID(),
        origin: NormalizedPoint,
        value: String,
        colorHex: String,
        strokeWidth: Double,
        fontSize: Double? = nil,
        opacity: Double = 1,
        fontName: String? = nil
    ) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: .text,
            start: origin,
            text: value,
            colorHex: colorHex,
            strokeWidth: strokeWidth,
            opacity: opacity,
            fontSize: fontSize,
            fontName: fontName
        )
    }

    public static func blur(
        id: UUID = UUID(),
        rect: NormalizedRect,
        colorHex: String = "#FFFFFF",
        strokeWidth: Double = 2
    ) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: .blur,
            rect: rect,
            colorHex: colorHex,
            strokeWidth: strokeWidth
        )
    }

    public func translatedBy(pixelDelta: CGPoint, imageSize: CGSize) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: tool,
            start: start?.translatedBy(pixelDelta: pixelDelta, imageSize: imageSize),
            end: end?.translatedBy(pixelDelta: pixelDelta, imageSize: imageSize),
            rect: rect?.translatedBy(pixelDelta: pixelDelta, imageSize: imageSize),
            text: text,
            colorHex: colorHex,
            fillColorHex: fillColorHex,
            strokeWidth: strokeWidth,
            opacity: opacity,
            fontSize: fontSize,
            fontName: fontName
        )
    }

    public func styled(
        colorHex: String? = nil,
        strokeWidth: Double? = nil,
        opacity: Double? = nil,
        fontSize: Double? = nil,
        fontName: String? = nil
    ) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: tool,
            start: start,
            end: end,
            rect: rect,
            text: text,
            colorHex: colorHex ?? self.colorHex,
            fillColorHex: fillColorHex,
            strokeWidth: strokeWidth ?? self.strokeWidth,
            opacity: opacity ?? self.opacity,
            fontSize: fontSize ?? self.fontSize,
            fontName: fontName ?? self.fontName
        )
    }

    public func replacingText(_ value: String) -> AnnotationElement {
        AnnotationElement(
            id: id,
            tool: tool,
            start: start,
            end: end,
            rect: rect,
            text: value,
            colorHex: colorHex,
            fillColorHex: fillColorHex,
            strokeWidth: strokeWidth,
            opacity: opacity,
            fontSize: fontSize,
            fontName: fontName
        )
    }
}

public struct AnnotationSessionMetadata: Codable, Equatable, Sendable {
    public let mode: AnnotationSessionMode
    public let redactionStyle: AnnotationRedactionStyle
    public let tools: [AnnotationTool]
    public let elements: [AnnotationElement]

    public init(
        mode: AnnotationSessionMode,
        redactionStyle: AnnotationRedactionStyle = .blur,
        elements: [AnnotationElement]
    ) {
        self.mode = mode
        self.redactionStyle = redactionStyle
        self.elements = elements

        var seen: Set<AnnotationTool> = []
        tools = elements.compactMap { element in
            guard !seen.contains(element.tool) else {
                return nil
            }
            seen.insert(element.tool)
            return element.tool
        }
    }
}
