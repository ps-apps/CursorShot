import AppKit
import CoreImage
import cshotCore
import Foundation

final class AnnotationCanvasView: NSView {
    var tool: AnnotationTool = .arrow {
        didSet {
            finishInlineTextEditing(commit: true)
            dragStart = nil
            dragCurrent = nil
            refreshCursorForCurrentMouseLocation()
            needsDisplay = true
        }
    }

    private func refreshCursorForCurrentMouseLocation() {
        guard let window else {
            return
        }
        updateCursor(forPointInWindow: window.mouseLocationOutsideOfEventStream)
    }

    var colorHex = "#FF453A"
    var strokeWidth: Double = 4
    var opacity: Double = 1
    var fontSize: Double = 28
    var fontName = "system"
    var onElementsChanged: (() -> Void)?
    var onToolChangedBySelection: ((AnnotationTool) -> Void)?
    private(set) var elements: [AnnotationElement] = []

    var isEditingInlineText: Bool {
        activeTextOrigin != nil
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var currentImage: CGImage {
        image
    }

    private struct HistorySnapshot {
        let image: CGImage
        let elements: [AnnotationElement]
    }

    private var image: CGImage
    private var nsImage: NSImage
    private var blurredNSImage: NSImage
    private var imageSize: CGSize
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var undoStack: [HistorySnapshot] = []
    private var redoStack: [HistorySnapshot] = []
    private var selectedElementID: UUID?
    private var movingElementID: UUID?
    private var moveStartImagePoint: CGPoint?
    private var moveOriginalElement: AnnotationElement?
    private var moveHistoryRecorded = false
    private var activeTextValue = ""
    private var activeTextOrigin: CGPoint?
    private var activeTextElementID: UUID?
    private var isFinishingInlineText = false

    init(image: CGImage) {
        self.image = image
        self.nsImage = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        self.blurredNSImage = AnnotationCanvasView.makeBlurredImage(from: image)
        self.imageSize = CGSize(width: image.width, height: image.height)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(forPointInWindow: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(forPointInWindow: event.locationInWindow)
    }

    private func updateCursor(forPointInWindow windowPoint: NSPoint) {
        if movingElementID != nil {
            NSCursor.closedHand.set()
            return
        }

        let point = convert(windowPoint, from: nil)
        let canvas = canvasRect()
        let cursor: NSCursor
        if !canvas.contains(point) {
            cursor = .arrow
        } else if tool == .crop {
            cursor = .crosshair
        } else if hitTestElement(at: point, in: canvas) != nil {
            cursor = .openHand
        } else if tool == .text {
            cursor = .iBeam
        } else {
            cursor = .crosshair
        }
        cursor.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        bounds.fill()

        let rect = canvasRect()
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: -6, dy: -6), xRadius: 8, yRadius: 8).fill()

        nsImage.draw(in: rect)

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        for element in elements where element.id != activeTextElementID {
            draw(element, in: rect)
        }
        drawInlineText(in: rect)
        if let draftElement {
            draw(draftElement, in: rect, isDraft: true)
        }
        if tool == .crop {
            drawCropPreview(in: rect)
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        if let selectedElement {
            drawSelection(for: selectedElement, in: rect)
        }

        NSColor.white.withAlphaComponent(0.22).setStroke()
        let outline = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        outline.lineWidth = 1
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        finishInlineTextEditing(commit: true)
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        let canvas = canvasRect()
        guard canvas.contains(point), let imagePoint = imagePoint(from: point) else {
            selectedElementID = nil
            needsDisplay = true
            return
        }

        if tool == .crop {
            selectedElementID = nil
            dragStart = imagePoint
            dragCurrent = imagePoint
            needsDisplay = true
            return
        }

        if let hitElement = hitTestElement(at: point, in: canvas) {
            selectElement(hitElement)
            if event.clickCount >= 2, hitElement.tool == .text {
                beginTextEditing(existing: hitElement, in: canvas)
                return
            }

            movingElementID = hitElement.id
            moveStartImagePoint = imagePoint
            moveOriginalElement = hitElement
            moveHistoryRecorded = false
            return
        }

        selectedElementID = nil

        if tool == .text {
            beginTextEditing(at: imagePoint, in: canvas)
            return
        }

        dragStart = imagePoint
        dragCurrent = imagePoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if movingElementID != nil {
            NSCursor.closedHand.set()
            guard let imagePoint = imagePoint(from: point) else {
                return
            }
            updateMove(to: imagePoint)
            return
        }

        guard dragStart != nil else {
            return
        }

        dragCurrent = imagePoint(from: point)
        needsDisplay = true
    }
    

    override func mouseUp(with event: NSEvent) {
        if movingElementID != nil {
            movingElementID = nil
            moveStartImagePoint = nil
            moveOriginalElement = nil
            moveHistoryRecorded = false
            updateCursor(forPointInWindow: event.locationInWindow)
            onElementsChanged?()
            return
        }

        guard let dragStart else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let endPoint = imagePoint(from: point) ?? dragCurrent ?? dragStart
        self.dragStart = nil
        dragCurrent = nil

        if tool == .crop {
            applyCrop(from: dragStart, to: endPoint)
            return
        }

        guard let element = elementForDrag(from: dragStart, to: endPoint) else {
            needsDisplay = true
            return
        }

        addElement(element)
    }

    private func applyCrop(from start: CGPoint, to end: CGPoint) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).intersection(CGRect(origin: .zero, size: imageSize)).integral

        guard rect.width >= 12, rect.height >= 12 else {
            needsDisplay = true
            return
        }

        guard let cropped = image.cropping(to: rect) else {
            needsDisplay = true
            return
        }

        recordHistory()

        let newSize = CGSize(width: cropped.width, height: cropped.height)
        let oldSize = imageSize
        elements = elements.compactMap { element in
            translate(element, fromCrop: rect, oldSize: oldSize, newSize: newSize)
        }

        image = cropped
        imageSize = newSize
        nsImage = NSImage(cgImage: cropped, size: newSize)
        blurredNSImage = AnnotationCanvasView.makeBlurredImage(from: cropped)
        selectedElementID = nil
        needsDisplay = true
        onElementsChanged?()
    }

    private func translate(
        _ element: AnnotationElement,
        fromCrop crop: CGRect,
        oldSize: CGSize,
        newSize: CGSize
    ) -> AnnotationElement? {
        switch element.tool {
        case .arrow, .line:
            guard let start = element.start?.pixelPoint(in: oldSize),
                  let end = element.end?.pixelPoint(in: oldSize) else {
                return nil
            }
            let segment = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            guard crop.intersects(segment) else {
                return nil
            }
            return AnnotationElement(
                id: element.id,
                tool: element.tool,
                start: NormalizedPoint(pixelPoint: shifted(start, by: crop.origin), imageSize: newSize),
                end: NormalizedPoint(pixelPoint: shifted(end, by: crop.origin), imageSize: newSize),
                colorHex: element.colorHex,
                fillColorHex: element.fillColorHex,
                strokeWidth: element.strokeWidth,
                opacity: element.opacity,
                fontSize: element.fontSize,
                fontName: element.fontName
            )
        case .rectangle, .oval, .highlight, .blur:
            guard let pixelRect = element.rect?.pixelRect(in: oldSize) else {
                return nil
            }
            let clipped = pixelRect.intersection(crop)
            guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else {
                return nil
            }
            let shiftedRect = CGRect(
                x: clipped.minX - crop.minX,
                y: clipped.minY - crop.minY,
                width: clipped.width,
                height: clipped.height
            )
            return AnnotationElement(
                id: element.id,
                tool: element.tool,
                rect: NormalizedRect(pixelRect: shiftedRect, imageSize: newSize),
                text: element.text,
                colorHex: element.colorHex,
                fillColorHex: element.fillColorHex,
                strokeWidth: element.strokeWidth,
                opacity: element.opacity,
                fontSize: element.fontSize,
                fontName: element.fontName
            )
        case .text:
            guard let origin = element.start?.pixelPoint(in: oldSize) else {
                return nil
            }
            guard crop.contains(origin) else {
                return nil
            }
            return AnnotationElement(
                id: element.id,
                tool: .text,
                start: NormalizedPoint(pixelPoint: shifted(origin, by: crop.origin), imageSize: newSize),
                text: element.text,
                colorHex: element.colorHex,
                strokeWidth: element.strokeWidth,
                opacity: element.opacity,
                fontSize: element.fontSize,
                fontName: element.fontName
            )
        case .crop:
            return nil
        }
    }

    private func shifted(_ point: CGPoint, by origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    override func keyDown(with event: NSEvent) {
        if handleInlineTextKeyEvent(event) {
            return
        }

        super.keyDown(with: event)
    }

    func handleInlineTextKeyEvent(_ event: NSEvent) -> Bool {
        guard isEditingInlineText else {
            return false
        }

        switch event.keyCode {
        case 36, 76:
            finishInlineTextEditing(commit: true)
            return true
        case 53:
            finishInlineTextEditing(commit: false)
            return true
        case 51, 117:
            if !activeTextValue.isEmpty {
                activeTextValue.removeLast()
                needsDisplay = true
            }
            return true
        default:
            break
        }

        guard let characters = event.characters, !characters.isEmpty else {
            return true
        }

        for scalar in characters.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) {
            activeTextValue.append(String(scalar))
        }
        needsDisplay = true
        return true
    }

    func undo() {
        finishInlineTextEditing(commit: true)
        guard let previous = undoStack.last else {
            return
        }

        undoStack = Array(undoStack.dropLast())
        redoStack = redoStack + [currentSnapshot()]
        apply(snapshot: previous)
    }

    func redo() {
        finishInlineTextEditing(commit: true)
        guard let next = redoStack.last else {
            return
        }

        redoStack = Array(redoStack.dropLast())
        undoStack = undoStack + [currentSnapshot()]
        apply(snapshot: next)
    }

    private func currentSnapshot() -> HistorySnapshot {
        HistorySnapshot(image: image, elements: elements)
    }

    private func apply(snapshot: HistorySnapshot) {
        let imageChanged = snapshot.image !== image
        image = snapshot.image
        imageSize = CGSize(width: image.width, height: image.height)
        if imageChanged {
            nsImage = NSImage(cgImage: image, size: imageSize)
            blurredNSImage = AnnotationCanvasView.makeBlurredImage(from: image)
        }
        elements = snapshot.elements
        selectedElementID = nil
        needsDisplay = true
        onElementsChanged?()
    }

    func deleteSelection() {
        finishInlineTextEditing(commit: true)
        guard let selectedElementID, elements.contains(where: { $0.id == selectedElementID }) else {
            return
        }

        recordHistory()
        elements.removeAll { $0.id == selectedElementID }
        self.selectedElementID = nil
        needsDisplay = true
        onElementsChanged?()
    }

    func applyCurrentStyleToSelection() {
        if isEditingInlineText {
            needsDisplay = true
        }

        guard let selectedElementID,
              let index = elements.firstIndex(where: { $0.id == selectedElementID }) else {
            return
        }

        let styledElement = elements[index].styled(
            colorHex: colorHex,
            strokeWidth: strokeWidth,
            opacity: opacity,
            fontSize: fontSize,
            fontName: fontName
        )
        guard styledElement != elements[index] else {
            return
        }

        recordHistory()
        elements[index] = styledElement
        needsDisplay = true
        onElementsChanged?()
    }

    func finishInlineTextEditing(commit: Bool) {
        guard isEditingInlineText, !isFinishingInlineText else {
            return
        }

        isFinishingInlineText = true
        let value = activeTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = activeTextOrigin
        let elementID = activeTextElementID
        activeTextValue = ""
        activeTextOrigin = nil
        activeTextElementID = nil
        window?.makeFirstResponder(self)
        isFinishingInlineText = false

        guard commit else {
            needsDisplay = true
            return
        }

        if let elementID, let index = elements.firstIndex(where: { $0.id == elementID }) {
            recordHistory()
            if value.isEmpty {
                elements.remove(at: index)
                selectedElementID = nil
            } else {
                elements[index] = elements[index]
                    .styled(colorHex: colorHex, opacity: opacity, fontSize: fontSize, fontName: fontName)
                    .replacingText(value)
                selectedElementID = elementID
            }
            needsDisplay = true
            onElementsChanged?()
            return
        }

        guard let origin, !value.isEmpty else {
            needsDisplay = true
            return
        }

        addElement(
            .text(
                origin: NormalizedPoint(pixelPoint: origin, imageSize: imageSize),
                value: value,
                colorHex: colorHex,
                strokeWidth: strokeWidth,
                fontSize: fontSize,
                opacity: opacity,
                fontName: fontName
            )
        )
    }

    private var draftElement: AnnotationElement? {
        guard let dragStart, let dragCurrent else {
            return nil
        }

        return elementForDrag(from: dragStart, to: dragCurrent, allowSmall: true)
    }

    private var selectedElement: AnnotationElement? {
        guard let selectedElementID else {
            return nil
        }

        return elements.first { $0.id == selectedElementID }
    }

    private func beginTextEditing(at imagePoint: CGPoint, in canvas: CGRect) {
        beginTextEditing(
            value: "",
            imagePoint: imagePoint,
            elementID: nil,
            canvas: canvas
        )
    }

    private func beginTextEditing(existing element: AnnotationElement, in canvas: CGRect) {
        guard let start = element.start else {
            return
        }

        beginTextEditing(
            value: element.text ?? "",
            imagePoint: start.pixelPoint(in: imageSize),
            elementID: element.id,
            canvas: canvas
        )
    }

    private func beginTextEditing(
        value: String,
        imagePoint: CGPoint,
        elementID: UUID?,
        canvas: CGRect
    ) {
        activeTextValue = value
        activeTextOrigin = imagePoint
        activeTextElementID = elementID
        selectedElementID = elementID
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func addElement(_ element: AnnotationElement) {
        recordHistory()
        elements = elements + [element]
        selectedElementID = element.id
        syncStyle(from: element)
        redoStack = []
        needsDisplay = true
        onElementsChanged?()
    }

    private func recordHistory() {
        if let last = undoStack.last, last.image === image, last.elements == elements {
            return
        }

        undoStack = Array((undoStack + [currentSnapshot()]).suffix(80))
        redoStack = []
    }

    private func selectElement(_ element: AnnotationElement) {
        selectedElementID = element.id
        syncStyle(from: element)
        needsDisplay = true
        onElementsChanged?()
    }

    private func syncStyle(from element: AnnotationElement) {
        tool = element.tool
        colorHex = element.colorHex
        strokeWidth = element.strokeWidth
        opacity = element.opacity ?? (element.tool == .highlight ? 0.35 : 1)
        fontSize = element.fontSize ?? fontSize
        fontName = element.fontName ?? "system"
        onToolChangedBySelection?(element.tool)
    }

    private func updateMove(to imagePoint: CGPoint) {
        guard let movingElementID,
              let moveStartImagePoint,
              let moveOriginalElement,
              let index = elements.firstIndex(where: { $0.id == movingElementID }) else {
            return
        }

        let delta = CGPoint(
            x: imagePoint.x - moveStartImagePoint.x,
            y: imagePoint.y - moveStartImagePoint.y
        )
        guard hypot(delta.x, delta.y) >= 0.5 else {
            return
        }

        if !moveHistoryRecorded {
            recordHistory()
            moveHistoryRecorded = true
        }

        elements[index] = moveOriginalElement.translatedBy(pixelDelta: delta, imageSize: imageSize)
        needsDisplay = true
    }

    private func elementForDrag(from start: CGPoint, to end: CGPoint, allowSmall: Bool = false) -> AnnotationElement? {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        switch tool {
        case .arrow:
            guard allowSmall || distance >= 8 else {
                return nil
            }

            return .arrow(
                start: NormalizedPoint(pixelPoint: start, imageSize: imageSize),
                end: NormalizedPoint(pixelPoint: end, imageSize: imageSize),
                colorHex: colorHex,
                strokeWidth: strokeWidth,
                opacity: opacity
            )
        case .line:
            guard allowSmall || distance >= 8 else {
                return nil
            }

            return .line(
                start: NormalizedPoint(pixelPoint: start, imageSize: imageSize),
                end: NormalizedPoint(pixelPoint: end, imageSize: imageSize),
                colorHex: colorHex,
                strokeWidth: strokeWidth,
                opacity: opacity
            )
        case .rectangle:
            guard allowSmall || (rect.width >= 8 && rect.height >= 8) else {
                return nil
            }

            return .rectangle(
                rect: NormalizedRect(pixelRect: rect, imageSize: imageSize),
                colorHex: colorHex,
                strokeWidth: strokeWidth,
                opacity: opacity
            )
        case .oval:
            guard allowSmall || (rect.width >= 8 && rect.height >= 8) else {
                return nil
            }

            return .oval(
                rect: NormalizedRect(pixelRect: rect, imageSize: imageSize),
                colorHex: colorHex,
                strokeWidth: strokeWidth,
                opacity: opacity
            )
        case .highlight:
            guard allowSmall || (rect.width >= 8 && rect.height >= 8) else {
                return nil
            }

            return .highlight(
                rect: NormalizedRect(pixelRect: rect, imageSize: imageSize),
                colorHex: colorHex,
                opacity: opacity
            )
        case .blur:
            guard allowSmall || (rect.width >= 8 && rect.height >= 8) else {
                return nil
            }

            return .blur(
                rect: NormalizedRect(pixelRect: rect, imageSize: imageSize),
                colorHex: colorHex,
                strokeWidth: strokeWidth
            )
        case .text:
            return nil
        case .crop:
            return nil
        }
    }

    private func hitTestElement(at point: CGPoint, in canvas: CGRect) -> AnnotationElement? {
        elements.reversed().first { element in
            guard element.id != activeTextElementID else {
                return false
            }

            return contains(point, element: element, in: canvas)
        }
    }

    private func contains(_ point: CGPoint, element: AnnotationElement, in canvas: CGRect) -> Bool {
        let tolerance = max(7, viewStrokeWidth(element, in: canvas) + 5)

        switch element.tool {
        case .arrow, .line:
            guard let start = element.start, let end = element.end else {
                return false
            }
            return distance(from: point, toSegmentStart: viewPoint(start, in: canvas), end: viewPoint(end, in: canvas)) <= tolerance
        case .rectangle, .oval, .highlight, .blur:
            guard let rect = element.rect else {
                return false
            }
            return viewRect(rect, in: canvas).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .text:
            guard let textRect = textViewRect(for: element, in: canvas) else {
                return false
            }
            return textRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .crop:
            return false
        }
    }

    private func draw(_ element: AnnotationElement, in canvas: CGRect, isDraft: Bool = false) {
        switch element.tool {
        case .arrow:
            drawArrow(element, in: canvas, isDraft: isDraft)
        case .line:
            drawLine(element, in: canvas, isDraft: isDraft)
        case .rectangle:
            drawRectangle(element, in: canvas, isDraft: isDraft)
        case .oval:
            drawOval(element, in: canvas, isDraft: isDraft)
        case .highlight:
            drawHighlight(element, in: canvas, isDraft: isDraft)
        case .text:
            drawText(element, in: canvas)
        case .blur:
            drawBlur(element, in: canvas, isDraft: isDraft)
        case .crop:
            return
        }
    }

    private func drawArrow(_ element: AnnotationElement, in canvas: CGRect, isDraft: Bool) {
        guard let start = element.start, let end = element.end else {
            return
        }

        let startPoint = viewPoint(start, in: canvas)
        let endPoint = viewPoint(end, in: canvas)
        let lineWidth = viewStrokeWidth(element, in: canvas)
        let color = nsColor(from: element.colorHex)
            .withAlphaComponent(elementOpacity(element, isDraft: isDraft))

        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: startPoint)
        path.line(to: endPoint)
        path.stroke()

        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let headLength = max(11, lineWidth * 4)
        let headAngle = CGFloat.pi / 7
        let first = CGPoint(
            x: endPoint.x - headLength * cos(angle - headAngle),
            y: endPoint.y - headLength * sin(angle - headAngle)
        )
        let second = CGPoint(
            x: endPoint.x - headLength * cos(angle + headAngle),
            y: endPoint.y - headLength * sin(angle + headAngle)
        )

        let head = NSBezierPath()
        head.move(to: endPoint)
        head.line(to: first)
        head.line(to: second)
        head.close()
        head.fill()
    }

    private func drawLine(_ element: AnnotationElement, in canvas: CGRect, isDraft: Bool) {
        guard let start = element.start, let end = element.end else {
            return
        }

        let path = NSBezierPath()
        path.lineWidth = viewStrokeWidth(element, in: canvas)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: viewPoint(start, in: canvas))
        path.line(to: viewPoint(end, in: canvas))
        nsColor(from: element.colorHex)
            .withAlphaComponent(elementOpacity(element, isDraft: isDraft))
            .setStroke()
        path.stroke()
    }

    private func drawRectangle(_ element: AnnotationElement, in canvas: CGRect, isDraft: Bool) {
        guard let normalizedRect = element.rect else {
            return
        }

        let rect = viewRect(normalizedRect, in: canvas)
        nsColor(from: element.colorHex)
            .withAlphaComponent(elementOpacity(element, isDraft: isDraft))
            .setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = viewStrokeWidth(element, in: canvas)
        path.stroke()
    }

    private func drawOval(_ element: AnnotationElement, in canvas: CGRect, isDraft: Bool) {
        guard let normalizedRect = element.rect else {
            return
        }

        let rect = viewRect(normalizedRect, in: canvas)
        nsColor(from: element.colorHex)
            .withAlphaComponent(elementOpacity(element, isDraft: isDraft))
            .setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = viewStrokeWidth(element, in: canvas)
        path.stroke()
    }

    private func drawHighlight(_ element: AnnotationElement, in canvas: CGRect, isDraft: Bool) {
        guard let normalizedRect = element.rect else {
            return
        }

        let rect = viewRect(normalizedRect, in: canvas)
        nsColor(from: element.colorHex)
            .withAlphaComponent(elementOpacity(element, fallback: 0.35, isDraft: isDraft))
            .setFill()
        NSBezierPath(rect: rect).fill()
    }

    private func drawText(_ element: AnnotationElement, in canvas: CGRect) {
        guard let text = element.text, !text.isEmpty,
              let rect = textViewRect(for: element, in: canvas) else {
            return
        }

        let fontSize = viewFontSize(for: element, in: canvas)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont(size: fontSize, name: element.fontName ?? "system"),
            .foregroundColor: nsColor(from: element.colorHex)
                .withAlphaComponent(CGFloat(element.opacity ?? 1)),
            .strokeColor: NSColor.black.withAlphaComponent(0.44),
            .strokeWidth: -2
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(at: CGPoint(x: rect.minX, y: rect.minY))
    }

    private func drawInlineText(in canvas: CGRect) {
        guard let activeTextOrigin else {
            return
        }

        let isPlaceholder = activeTextValue.isEmpty
        let displayedText = isPlaceholder ? "Type annotation" : activeTextValue
        let activeElement = AnnotationElement.text(
            origin: NormalizedPoint(pixelPoint: activeTextOrigin, imageSize: imageSize),
            value: displayedText,
            colorHex: colorHex,
            strokeWidth: strokeWidth,
            fontSize: fontSize,
            opacity: isPlaceholder ? 0.45 : opacity,
            fontName: fontName
        )
        guard let rect = textViewRect(for: activeElement, in: canvas) else {
            return
        }

        let bg = rect.insetBy(dx: -6, dy: -4)
        NSColor.windowBackgroundColor.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5)
        outline.lineWidth = 1.4
        outline.stroke()

        drawText(activeElement, in: canvas)

        let viewSize = viewFontSize(for: activeElement, in: canvas)
        let font = textFont(size: viewSize, name: fontName)
        let typedWidth = activeTextValue.isEmpty
            ? 0
            : NSAttributedString(string: activeTextValue, attributes: [.font: font]).size().width
        let caretX = min(rect.maxX - 2, rect.minX + typedWidth + 1)
        let caret = NSBezierPath()
        caret.move(to: CGPoint(x: caretX, y: rect.minY + 1))
        caret.line(to: CGPoint(x: caretX, y: rect.maxY - 1))
        caret.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        caret.stroke()
    }

    private func drawCropPreview(in canvas: CGRect) {
        guard let dragStart, let dragCurrent else {
            return
        }

        let pixelRect = CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
        guard pixelRect.width > 0, pixelRect.height > 0 else {
            return
        }

        let rect = viewRect(NormalizedRect(pixelRect: pixelRect, imageSize: imageSize), in: canvas)
        NSColor.black.withAlphaComponent(0.46).setFill()
        let overlay = NSBezierPath(rect: canvas)
        overlay.append(NSBezierPath(rect: rect).reversed)
        overlay.fill()

        NSColor.systemYellow.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 1.5
        outline.setLineDash([6, 4], count: 2, phase: 0)
        outline.stroke()

        let label = NSAttributedString(
            string: "Crop",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.black,
                .backgroundColor: NSColor.systemYellow
            ]
        )
        label.draw(at: CGPoint(x: rect.minX + 4, y: rect.maxY - 16))
    }

    private func drawBlur(_ element: AnnotationElement, in canvas: CGRect, isDraft: Bool) {
        guard let normalizedRect = element.rect else {
            return
        }

        let rect = viewRect(normalizedRect, in: canvas)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        blurredNSImage.draw(in: canvas)
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.white.withAlphaComponent(isDraft ? 0.12 : 0.05).setFill()
        NSBezierPath(rect: rect).fill()

        NSColor.white.withAlphaComponent(0.58).setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = max(1, viewStrokeWidth(element, in: canvas) * 0.58)
        outline.stroke()

        let label = NSAttributedString(
            string: "Blur",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.82)
            ]
        )
        label.draw(at: CGPoint(x: rect.minX + 6, y: rect.maxY - 18))
    }

    private func drawSelection(for element: AnnotationElement, in canvas: CGRect) {
        guard element.id != activeTextElementID,
              let bounds = elementBounds(element, in: canvas)?.insetBy(dx: -7, dy: -7),
              bounds.width > 1,
              bounds.height > 1 else {
            return
        }

        let path = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.92).setStroke()
        path.stroke()

        for point in [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.midX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.midY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.midX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.midY)
        ] {
            let handle = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).stroke()
        }
    }

    private func canvasRect() -> CGRect {
        let available = bounds.insetBy(dx: 18, dy: 18)
        guard available.width > 0, available.height > 0 else {
            return .zero
        }

        let aspect = imageSize.width / max(imageSize.height, 1)
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }

        return CGRect(
            x: available.midX - width / 2,
            y: available.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint? {
        let canvas = canvasRect()
        guard canvas.width > 0, canvas.height > 0 else {
            return nil
        }

        let scale = canvas.width / imageSize.width
        return CGPoint(
            x: min(max((viewPoint.x - canvas.minX) / scale, 0), imageSize.width),
            y: min(max((canvas.maxY - viewPoint.y) / scale, 0), imageSize.height)
        )
    }

    private func viewPoint(_ normalizedPoint: NormalizedPoint, in canvas: CGRect) -> CGPoint {
        let pixel = normalizedPoint.pixelPoint(in: imageSize)
        let scale = canvas.width / imageSize.width
        return CGPoint(
            x: canvas.minX + pixel.x * scale,
            y: canvas.maxY - pixel.y * scale
        )
    }

    private func viewRect(_ normalizedRect: NormalizedRect, in canvas: CGRect) -> CGRect {
        let pixelRect = normalizedRect.pixelRect(in: imageSize)
        let scale = canvas.width / imageSize.width
        return CGRect(
            x: canvas.minX + pixelRect.minX * scale,
            y: canvas.maxY - pixelRect.maxY * scale,
            width: pixelRect.width * scale,
            height: pixelRect.height * scale
        )
    }

    private func elementBounds(_ element: AnnotationElement, in canvas: CGRect) -> CGRect? {
        switch element.tool {
        case .arrow, .line:
            guard let start = element.start, let end = element.end else {
                return nil
            }

            let startPoint = viewPoint(start, in: canvas)
            let endPoint = viewPoint(end, in: canvas)
            return CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
        case .rectangle, .oval, .highlight, .blur:
            guard let rect = element.rect else {
                return nil
            }

            return viewRect(rect, in: canvas)
        case .text:
            return textViewRect(for: element, in: canvas)
        case .crop:
            return nil
        }
    }

    private func textViewRect(for element: AnnotationElement, in canvas: CGRect) -> CGRect? {
        guard let start = element.start else {
            return nil
        }

        let point = viewPoint(start, in: canvas)
        let size = viewFontSize(for: element, in: canvas)
        let font = textFont(size: size, name: element.fontName ?? "system")
        let lineHeight = font.ascender - font.descender + font.leading
        let available = max(120, canvas.maxX - point.x - 10)
        return CGRect(
            x: point.x,
            y: point.y - lineHeight,
            width: available,
            height: lineHeight
        )
    }

    private func viewFontSize(for element: AnnotationElement, in canvas: CGRect) -> CGFloat {
        max(10, CGFloat(element.fontSize ?? 28) * canvas.width / imageSize.width)
    }

    private func viewStrokeWidth(_ element: AnnotationElement, in canvas: CGRect) -> CGFloat {
        max(1.5, CGFloat(element.strokeWidth) * canvas.width / imageSize.width)
    }

    private func elementOpacity(_ element: AnnotationElement, fallback: Double = 1, isDraft: Bool) -> CGFloat {
        CGFloat(element.opacity ?? fallback) * (isDraft ? 0.68 : 1)
    }

    private func scaledFontSize(_ size: Double) -> CGFloat {
        let canvas = canvasRect()
        guard canvas.width > 0 else {
            return CGFloat(size)
        }

        return max(10, CGFloat(size) * canvas.width / imageSize.width)
    }

    private func textFont(size: CGFloat, name: String) -> NSFont {
        switch name {
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

    private func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else {
            return 0
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont(size: fontSize, name: fontName)
        ]
        return NSAttributedString(string: text, attributes: attributes).size().width
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func nsColor(from hex: String) -> NSColor {
        let trimmed = hex
            .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))

        guard trimmed.count == 6, let rawValue = UInt32(trimmed, radix: 16) else {
            return .systemRed
        }

        return NSColor(
            red: CGFloat((rawValue & 0xFF0000) >> 16) / 255,
            green: CGFloat((rawValue & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rawValue & 0x0000FF) / 255,
            alpha: 1
        )
    }

    private static func makeBlurredImage(from image: CGImage) -> NSImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace
        ])
        let source = CIImage(cgImage: image)
        let blurred = source
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 18])
            .cropped(to: source.extent)

        guard let blurredImage = context.createCGImage(blurred, from: source.extent) else {
            return NSImage(cgImage: image, size: imageSize)
        }

        return NSImage(cgImage: blurredImage, size: imageSize)
    }
}
