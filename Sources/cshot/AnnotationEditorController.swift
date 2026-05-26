import AppKit
import CoreGraphics
import cshotCore
import Foundation

enum AnnotationEditorOutcome: Sendable {
    case committed(image: CGImage, elements: [AnnotationElement])
    case cancelled
}

@MainActor
final class AnnotationEditorController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<AnnotationEditorOutcome, Never>?

    func edit(image: CGImage) async -> AnnotationEditorOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.showEditor(for: image)
        }
    }

    private func showEditor(for image: CGImage) {
        NSApp.activate(ignoringOtherApps: true)

        let screen = preferredScreen()
        let visibleFrame = screen.visibleFrame
        let initialSize = preferredInitialSize(in: visibleFrame)

        let rootView = AnnotationEditorRootView(
            image: image,
            onCommit: { [weak self] finalImage, elements in
                self?.complete(.committed(image: finalImage, elements: elements))
            },
            onCancel: { [weak self] in
                self?.complete(.cancelled)
            }
        )

        let initialContentRect = CGRect(origin: .zero, size: initialSize)
        let editorWindow = NSWindow(
            contentRect: initialContentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        editorWindow.title = "Annotate Screenshot"
        editorWindow.isReleasedWhenClosed = false
        editorWindow.isRestorable = false
        editorWindow.backgroundColor = .windowBackgroundColor
        editorWindow.minSize = NSSize(width: 720, height: 480)
        editorWindow.contentMinSize = NSSize(width: 720, height: 480)
        editorWindow.contentView = rootView
        editorWindow.delegate = self

        editorWindow.makeFirstResponder(rootView.canvasView)
        window = editorWindow
        editorWindow.makeKeyAndOrderFront(nil)

        // AppKit on Sonoma+ shrinks the contentView to its Auto Layout fitting size during
        // makeKeyAndOrderFront, ignoring contentMinSize. Re-apply the desired frame and force
        // a layout pass so the canvas grows with the window.
        let targetContentRect = NSRect(
            x: visibleFrame.midX - initialSize.width / 2,
            y: visibleFrame.midY - initialSize.height / 2,
            width: initialSize.width,
            height: initialSize.height
        )
        let targetFrameRect = editorWindow.frameRect(forContentRect: targetContentRect)
        editorWindow.setFrame(targetFrameRect, display: true)
        rootView.needsLayout = true
        rootView.layoutSubtreeIfNeeded()
    }

    private func complete(_ outcome: AnnotationEditorOutcome) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        window?.delegate = nil
        window?.close()
        window = nil
        continuation.resume(returning: outcome)
    }

    func windowWillClose(_ notification: Notification) {
        complete(.cancelled)
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let visibleFrame = window.screen?.visibleFrame ?? newFrame
        return visibleFrame.insetBy(dx: 16, dy: 16)
    }

    private func preferredScreen() -> NSScreen {
        if let main = NSScreen.main {
            return main
        }
        if let first = NSScreen.screens.first {
            return first
        }
        let mouseLocation = NSEvent.mouseLocation
        if let match = NSScreen.screens.first(where: { $0.visibleFrame.contains(mouseLocation) }) {
            return match
        }
        return NSScreen()
    }

    private func preferredInitialSize(in visibleFrame: CGRect) -> CGSize {
        let availableWidth = max(800, visibleFrame.width - 64)
        let availableHeight = max(560, visibleFrame.height - 64)
        let targetWidth = max(1000, availableWidth * 0.7)
        let targetHeight = max(720, availableHeight * 0.78)
        let width = min(availableWidth, targetWidth)
        let height = min(availableHeight, targetHeight)
        return CGSize(width: width, height: height)
    }
}

private final class AnnotationEditorRootView: NSView {
    let canvasView: AnnotationCanvasView

    private let onCommit: (CGImage, [AnnotationElement]) -> Void
    private let onCancel: () -> Void
    private let inspectorView = AnnotationInspectorView()
    private let tools: [AnnotationTool] = [.arrow, .line, .rectangle, .oval, .highlight, .text, .blur, .crop]

    private let toolControl: NSSegmentedControl
    private let maximizeButton: NSButton
    private let undoButton: NSButton
    private let redoButton: NSButton
    private var hasCompleted = false

    init(
        image: CGImage,
        onCommit: @escaping (CGImage, [AnnotationElement]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        canvasView = AnnotationCanvasView(image: image)
        toolControl = NSSegmentedControl(
            labels: ["Arrow", "Line", "Box", "Oval", "Mark", "Text", "Blur", "Crop"],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        maximizeButton = AnnotationEditorRootView.makeIconButton(
            symbolName: "rectangle.expand.vertical",
            accessibilityLabel: "Maximize editor"
        )
        undoButton = AnnotationEditorRootView.makeIconButton(
            symbolName: "arrow.uturn.backward",
            accessibilityLabel: "Undo"
        )
        redoButton = AnnotationEditorRootView.makeIconButton(
            symbolName: "arrow.uturn.forward",
            accessibilityLabel: "Redo"
        )
        self.onCommit = onCommit
        self.onCancel = onCancel
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildLayout()
        configureControls()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleKeyEvent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if canvasView.isEditingInlineText {
            return canvasView.handleInlineTextKeyEvent(event)
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command), event.keyCode == 6 {
            if flags.contains(.shift) {
                canvasView.redo()
            } else {
                canvasView.undo()
            }
            refreshEditButtons()
            return true
        }

        switch event.keyCode {
        case 36, 76:
            commit()
            return true
        case 53:
            cancel()
            return true
        case 51, 117:
            canvasView.deleteSelection()
            refreshEditButtons()
            return true
        default:
            break
        }

        guard !flags.contains(.command) else {
            return false
        }

        switch event.keyCode {
        case 0:
            selectTool(.arrow)
            return true
        case 37:
            selectTool(.line)
            return true
        case 15:
            selectTool(.rectangle)
            return true
        case 31:
            selectTool(.oval)
            return true
        case 4:
            selectTool(.highlight)
            return true
        case 17:
            selectTool(.text)
            return true
        case 11:
            selectTool(.blur)
            return true
        case 8:
            selectTool(.crop)
            return true
        default:
            return false
        }
    }

    private func buildLayout() {
        let toolbar = NSVisualEffectView()
        toolbar.material = .headerView
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelButtonPressed))
        cancelButton.bezelStyle = .rounded
        cancelButton.toolTip = "Cancel without saving or pasting"

        let commitButton = NSButton(title: "Paste", target: self, action: #selector(commitButtonPressed))
        commitButton.bezelStyle = .rounded
        commitButton.keyEquivalent = "\r"
        commitButton.toolTip = "Save annotations and paste back"

        let title = NSTextField(labelWithString: "Annotate")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor

        stack.addArrangedSubview(toolControl)
        stack.addArrangedSubview(makeDivider())
        stack.addArrangedSubview(maximizeButton)
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(commitButton)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(stack)
        addSubview(toolbar)
        addSubview(canvasView)
        addSubview(divider)
        addSubview(inspectorView)

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        inspectorView.translatesAutoresizingMaskIntoConstraints = false

        let canvasMinHeight = canvasView.heightAnchor.constraint(greaterThanOrEqualToConstant: 460)
        canvasMinHeight.priority = .required

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 62),

            stack.topAnchor.constraint(equalTo: toolbar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),

            canvasView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvasMinHeight,

            divider.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.trailingAnchor.constraint(equalTo: inspectorView.leadingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            inspectorView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            inspectorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inspectorView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureControls() {
        toolControl.selectedSegment = 0
        toolControl.target = self
        toolControl.action = #selector(toolChanged)
        toolControl.segmentStyle = .rounded

        maximizeButton.target = self
        maximizeButton.action = #selector(maximizePressed)
        undoButton.target = self
        undoButton.action = #selector(undoPressed)
        redoButton.target = self
        redoButton.action = #selector(redoPressed)

        inspectorView.onColorChanged = { [weak self] colorHex in
            guard let self else {
                return
            }

            self.canvasView.colorHex = colorHex
            self.canvasView.applyCurrentStyleToSelection()
            self.restoreCanvasFocusIfNeeded()
        }
        inspectorView.onStrokeWidthChanged = { [weak self] strokeWidth in
            guard let self else {
                return
            }

            self.canvasView.strokeWidth = strokeWidth
            self.canvasView.applyCurrentStyleToSelection()
            self.restoreCanvasFocusIfNeeded()
        }
        inspectorView.onOpacityChanged = { [weak self] opacity in
            guard let self else {
                return
            }

            self.canvasView.opacity = opacity
            self.canvasView.applyCurrentStyleToSelection()
            self.restoreCanvasFocusIfNeeded()
        }
        inspectorView.onFontSizeChanged = { [weak self] fontSize in
            guard let self else {
                return
            }

            self.canvasView.fontSize = fontSize
            self.canvasView.applyCurrentStyleToSelection()
            self.restoreCanvasFocusIfNeeded()
        }
        inspectorView.onFontNameChanged = { [weak self] fontName in
            guard let self else {
                return
            }

            self.canvasView.fontName = fontName
            self.canvasView.applyCurrentStyleToSelection()
            self.restoreCanvasFocusIfNeeded()
        }

        canvasView.onElementsChanged = { [weak self] in
            self?.refreshEditButtons()
            self?.updateInspector()
        }
        canvasView.onToolChangedBySelection = { [weak self] tool in
            guard let self, let index = self.tools.firstIndex(of: tool) else {
                return
            }

            self.toolControl.selectedSegment = index
        }
        updateInspector()
        refreshEditButtons()
    }

    private func selectTool(_ tool: AnnotationTool) {
        guard let index = tools.firstIndex(of: tool) else {
            return
        }

        toolControl.selectedSegment = index
        canvasView.tool = tool
        configureDefaults(for: tool)
        updateInspector()
    }

    private func commit() {
        guard !hasCompleted else {
            return
        }

        hasCompleted = true
        canvasView.finishInlineTextEditing(commit: true)
        onCommit(canvasView.currentImage, canvasView.elements)
    }

    private func cancel() {
        guard !hasCompleted else {
            return
        }

        hasCompleted = true
        canvasView.finishInlineTextEditing(commit: false)
        onCancel()
    }

    @objc private func toolChanged() {
        let index = max(0, min(toolControl.selectedSegment, tools.count - 1))
        canvasView.tool = tools[index]
        configureDefaults(for: tools[index])
        updateInspector()
        window?.makeFirstResponder(canvasView)
    }

    @objc private func undoPressed() {
        canvasView.undo()
        refreshEditButtons()
        window?.makeFirstResponder(canvasView)
    }

    @objc private func redoPressed() {
        canvasView.redo()
        refreshEditButtons()
        window?.makeFirstResponder(canvasView)
    }

    @objc private func maximizePressed() {
        guard let window else {
            return
        }

        let screenFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? window.frame
        let target = screenFrame.insetBy(dx: 16, dy: 16)
        window.setFrame(target, display: true, animate: true)
        window.makeFirstResponder(canvasView)
    }

    @objc private func commitButtonPressed() {
        commit()
    }

    @objc private func cancelButtonPressed() {
        cancel()
    }

    private func refreshEditButtons() {
        undoButton.isEnabled = canvasView.canUndo
        redoButton.isEnabled = canvasView.canRedo
    }

    private func restoreCanvasFocusIfNeeded() {
        guard !canvasView.isEditingInlineText else {
            return
        }

        window?.makeFirstResponder(canvasView)
    }

    private func configureDefaults(for tool: AnnotationTool) {
        switch tool {
        case .highlight:
            canvasView.colorHex = "#FFD60A"
            canvasView.opacity = 0.35
            canvasView.strokeWidth = 1
        case .blur:
            canvasView.opacity = 1
            canvasView.strokeWidth = max(canvasView.strokeWidth, 8)
        case .text:
            canvasView.opacity = 1
            canvasView.strokeWidth = 4
            canvasView.fontSize = max(canvasView.fontSize, 28)
            if canvasView.fontName.isEmpty {
                canvasView.fontName = "system"
            }
        case .crop:
            return
        default:
            if canvasView.colorHex == "#FFD60A", canvasView.opacity < 0.5 {
                canvasView.colorHex = "#FF453A"
            }
            canvasView.opacity = 1
            canvasView.strokeWidth = min(max(canvasView.strokeWidth, 3), 8)
        }
    }

    private func updateInspector() {
        inspectorView.update(
            tool: canvasView.tool,
            colorHex: canvasView.colorHex,
            strokeWidth: canvasView.strokeWidth,
            opacity: canvasView.opacity,
            fontSize: canvasView.fontSize,
            fontName: canvasView.fontName
        )
    }

    private func makeDivider() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        return view
    }

    private static func makeIconButton(symbolName: String, accessibilityLabel: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.bezelStyle = .rounded
        button.imagePosition = .imageOnly
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }
}
