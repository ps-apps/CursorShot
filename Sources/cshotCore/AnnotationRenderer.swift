import AppKit
import CoreGraphics
import CoreImage
import Foundation

public enum AnnotationRendererError: LocalizedError {
    case contextCreationFailed
    case outputImageCreationFailed

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            "Could not create an annotation rendering context."
        case .outputImageCreationFailed:
            "Could not render the annotated screenshot."
        }
    }
}

public struct AnnotationRenderer {
    public init() {}

    public func render(image: CGImage, annotations: [AnnotationElement]) throws -> CGImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AnnotationRendererError.contextCreationFailed
        }

        let bounds = CGRect(origin: .zero, size: imageSize)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)

        let ciContext = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace
        ])
        let sourceImage = CIImage(cgImage: image)

        for annotation in annotations {
            draw(annotation, in: context, imageSize: imageSize, sourceImage: sourceImage, ciContext: ciContext)
        }

        guard let output = context.makeImage() else {
            throw AnnotationRendererError.outputImageCreationFailed
        }

        return output
    }

    private func draw(
        _ annotation: AnnotationElement,
        in context: CGContext,
        imageSize: CGSize,
        sourceImage: CIImage,
        ciContext: CIContext
    ) {
        switch annotation.tool {
        case .arrow:
            drawArrow(annotation, in: context, imageSize: imageSize)
        case .line:
            drawLine(annotation, in: context, imageSize: imageSize)
        case .rectangle:
            drawShape(annotation, in: context, imageSize: imageSize, shape: .rectangle)
        case .oval:
            drawShape(annotation, in: context, imageSize: imageSize, shape: .oval)
        case .highlight:
            drawHighlight(annotation, in: context, imageSize: imageSize)
        case .text:
            drawText(annotation, in: context, imageSize: imageSize)
        case .blur:
            drawBlur(annotation, in: context, imageSize: imageSize, sourceImage: sourceImage, ciContext: ciContext)
        case .crop:
            return
        }
    }

    private func drawArrow(_ annotation: AnnotationElement, in context: CGContext, imageSize: CGSize) {
        guard let start = annotation.start, let end = annotation.end else {
            return
        }

        let startPoint = contextPoint(start, imageSize: imageSize)
        let endPoint = contextPoint(end, imageSize: imageSize)
        let color = color(from: annotation.colorHex, alpha: opacity(annotation))
        let lineWidth = CGFloat(annotation.strokeWidth)

        context.saveGState()
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()

        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let headLength = max(14, lineWidth * 4.2)
        let headAngle = CGFloat.pi / 7
        let first = CGPoint(
            x: endPoint.x - headLength * cos(angle - headAngle),
            y: endPoint.y - headLength * sin(angle - headAngle)
        )
        let second = CGPoint(
            x: endPoint.x - headLength * cos(angle + headAngle),
            y: endPoint.y - headLength * sin(angle + headAngle)
        )

        context.move(to: endPoint)
        context.addLine(to: first)
        context.addLine(to: second)
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    private func drawLine(_ annotation: AnnotationElement, in context: CGContext, imageSize: CGSize) {
        guard let start = annotation.start, let end = annotation.end else {
            return
        }

        context.saveGState()
        context.setStrokeColor(color(from: annotation.colorHex, alpha: opacity(annotation)))
        context.setLineWidth(CGFloat(annotation.strokeWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: contextPoint(start, imageSize: imageSize))
        context.addLine(to: contextPoint(end, imageSize: imageSize))
        context.strokePath()
        context.restoreGState()
    }

    private enum ShapeKind {
        case rectangle
        case oval
    }

    private func drawShape(_ annotation: AnnotationElement, in context: CGContext, imageSize: CGSize, shape: ShapeKind) {
        guard let normalizedRect = annotation.rect else {
            return
        }

        let rect = contextRect(normalizedRect, imageSize: imageSize)
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        context.saveGState()
        if let fillColorHex = annotation.fillColorHex {
            context.setFillColor(color(from: fillColorHex, alpha: min(opacity(annotation), 0.45)))
            switch shape {
            case .rectangle:
                context.fill(rect)
            case .oval:
                context.fillEllipse(in: rect)
            }
        }

        context.setStrokeColor(color(from: annotation.colorHex, alpha: opacity(annotation)))
        context.setLineWidth(CGFloat(annotation.strokeWidth))
        switch shape {
        case .rectangle:
            context.stroke(rect)
        case .oval:
            context.strokeEllipse(in: rect)
        }
        context.restoreGState()
    }

    private func drawHighlight(_ annotation: AnnotationElement, in context: CGContext, imageSize: CGSize) {
        guard let normalizedRect = annotation.rect else {
            return
        }

        let rect = contextRect(normalizedRect, imageSize: imageSize)
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        context.saveGState()
        context.setBlendMode(.multiply)
        context.setFillColor(color(from: annotation.colorHex, alpha: opacity(annotation, fallback: 0.35)))
        context.fill(rect)
        context.restoreGState()
    }

    private func drawText(_ annotation: AnnotationElement, in context: CGContext, imageSize: CGSize) {
        guard let start = annotation.start,
              let text = annotation.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        let topLeft = start.pixelPoint(in: imageSize)
        let fontSize = CGFloat(annotation.fontSize ?? max(18, annotation.strokeWidth * 3.2 + 12))
        let nsFont = font(named: annotation.fontName, size: fontSize)
        let lineHeight = nsFont.ascender - nsFont.descender + nsFont.leading

        let color = NSColor(cgColor: color(from: annotation.colorHex, alpha: opacity(annotation))) ?? .systemRed
        let attributes: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: color,
            .strokeColor: NSColor.black.withAlphaComponent(0.42),
            .strokeWidth: -2
        ]

        let drawPoint = CGPoint(
            x: topLeft.x,
            y: imageSize.height - topLeft.y - lineHeight
        )

        context.saveGState()
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: attributes)
            .draw(at: drawPoint)
        NSGraphicsContext.current = previous
        context.restoreGState()
    }

    private func drawBlur(
        _ annotation: AnnotationElement,
        in context: CGContext,
        imageSize: CGSize,
        sourceImage: CIImage,
        ciContext: CIContext
    ) {
        guard let normalizedRect = annotation.rect else {
            return
        }

        let rect = contextRect(normalizedRect, imageSize: imageSize).integral
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        let blurredImage = sourceImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": max(8, min(32, annotation.strokeWidth * 2.5))])
            .cropped(to: rect)

        guard let blurredRegion = ciContext.createCGImage(blurredImage, from: rect) else {
            return
        }

        context.saveGState()
        context.clip(to: rect)
        context.draw(blurredRegion, in: rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.42).cgColor)
        context.setLineWidth(max(1, CGFloat(annotation.strokeWidth)))
        context.stroke(rect)
        context.restoreGState()
    }

    private func contextPoint(_ point: NormalizedPoint, imageSize: CGSize) -> CGPoint {
        let pixelPoint = point.pixelPoint(in: imageSize)
        return CGPoint(x: pixelPoint.x, y: imageSize.height - pixelPoint.y)
    }

    private func contextRect(_ rect: NormalizedRect, imageSize: CGSize) -> CGRect {
        let pixelRect = rect.pixelRect(in: imageSize)
        return CGRect(
            x: pixelRect.minX,
            y: imageSize.height - pixelRect.maxY,
            width: pixelRect.width,
            height: pixelRect.height
        )
    }

    private func opacity(_ annotation: AnnotationElement, fallback: Double = 1) -> CGFloat {
        CGFloat(annotation.opacity ?? fallback)
    }

    private func color(from hex: String, alpha: CGFloat = 1) -> CGColor {
        let trimmed = hex
            .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))

        guard trimmed.count == 6, let rawValue = UInt32(trimmed, radix: 16) else {
            return NSColor.systemRed.withAlphaComponent(alpha).cgColor
        }

        let red = CGFloat((rawValue & 0xFF0000) >> 16) / 255
        let green = CGFloat((rawValue & 0x00FF00) >> 8) / 255
        let blue = CGFloat(rawValue & 0x0000FF) / 255
        return NSColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
    }

    private func font(named fontName: String?, size: CGFloat) -> NSFont {
        switch fontName {
        case "rounded":
            if let descriptor = NSFont.systemFont(ofSize: size, weight: .bold)
                .fontDescriptor
                .withDesign(.rounded) {
                return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: .bold)
            }
            return .systemFont(ofSize: size, weight: .bold)
        case "monospaced":
            return .monospacedSystemFont(ofSize: size, weight: .bold)
        case "serif":
            return NSFont(name: "Georgia-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
        default:
            return .systemFont(ofSize: size, weight: .bold)
        }
    }
}
