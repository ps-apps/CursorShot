import AppKit
import ApplicationServices
import CursorShotCore
import Foundation

struct CaptureOverlayResult {
    let selection: CaptureSelection
    let shouldAnnotate: Bool
}

struct CaptureOverlayConfiguration {
    let cropEnabled: Bool
    let fullScreenEnabled: Bool
    let annotationEnabled: Bool

    static let allEnabled = CaptureOverlayConfiguration(
        cropEnabled: true,
        fullScreenEnabled: true,
        annotationEnabled: true
    )
}

@MainActor
final class CaptureOverlayController {
    enum Mode {
        case crop
        case window
        case screen

        var title: String {
            switch self {
            case .crop:
                "Crop"
            case .window:
                "Window"
            case .screen:
                "Full Screen"
            }
        }

        var symbolName: String {
            switch self {
            case .crop:
                "crop"
            case .window:
                "macwindow"
            case .screen:
                "display"
            }
        }
    }

    enum ToolbarOption: CaseIterable {
        case window
        case crop
        case screen
        case annotation

        init(mode: Mode) {
            switch mode {
            case .window:
                self = .window
            case .crop:
                self = .crop
            case .screen:
                self = .screen
            }
        }

        var mode: Mode? {
            switch self {
            case .window:
                .window
            case .crop:
                .crop
            case .screen:
                .screen
            case .annotation:
                nil
            }
        }
    }

    private var windows: [CaptureOverlayWindow] = []
    private let windowFinder: WindowCandidateFinder
    private let configuration: CaptureOverlayConfiguration
    private let completion: (CaptureOverlayResult?) -> Void
    private var inputInterceptor: CaptureOverlayInputInterceptor?
    private weak var activePointerView: CaptureOverlayView?
    private var isActive = false

    var mode: Mode = .window {
        didSet {
            focusedToolbarOption = ToolbarOption(mode: mode)
            hoveredWindow = nil
            dragStart = nil
            dragCurrent = nil
            redrawAll()
            invalidateCursorRects()
        }
    }

    var dragStart: CGPoint?
    var dragCurrent: CGPoint?
    var hoveredWindow: WindowCandidate?
    var windowCandidates: [WindowCandidate] = []
    var annotationArmed = false
    var focusedToolbarOption: ToolbarOption = .window
    private var isWindowPickerFrozen = false
    private var numberBuffer = ""
    private var numberBufferResetWorkItem: DispatchWorkItem?

    init(
        windowFinder: WindowCandidateFinder = WindowCandidateFinder(),
        configuration: CaptureOverlayConfiguration = .allEnabled,
        completion: @escaping (CaptureOverlayResult?) -> Void
    ) {
        self.windowFinder = windowFinder
        self.configuration = configuration
        self.completion = completion
    }

    func show() {
        guard !isActive else {
            return
        }

        isActive = true
        let allCandidates = windowFinder.candidates(scope: .all)
        updateWindowCandidates(allCandidates, context: "CoreGraphics")
        windows = NSScreen.screens.map { screen in
            CaptureOverlayWindow(screen: screen, controller: self)
        }

        inputInterceptor = CaptureOverlayInputInterceptor { [weak self] event in
            self?.handleInputEvent(event)
        }
        if inputInterceptor?.start() != true {
            inputInterceptor = nil
            DebugLog.write("overlay input interceptor failed to start")
        } else {
            DebugLog.write("overlay input interceptor started")
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        if let firstWindow = windows.first {
            firstWindow.makeKeyAndOrderFront(nil)
            firstWindow.makeMain()
            firstWindow.makeFirstResponder(firstWindow.overlayView)
        }
        DebugLog.write("overlay windows ordered count=\(windows.count)")

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let screenCaptureKitCandidates = await self.windowFinder.screenCaptureKitCandidates()
            guard self.isActive else {
                return
            }

            self.updateWindowCandidates(
                allCandidates + screenCaptureKitCandidates,
                context: "CoreGraphics+ScreenCaptureKit"
            )
        }
    }

    func cancel() {
        guard isActive else {
            return
        }

        closeWindows()
        completion(nil)
    }

    func beginDrag(at point: CGPoint) {
        guard mode == .crop else {
            return
        }

        dragStart = point
        dragCurrent = point
        hoveredWindow = nil
        redrawAll()
    }

    func updateDrag(to point: CGPoint) {
        guard mode == .crop else {
            return
        }

        dragCurrent = point
        redrawAll()
    }

    func finishDrag(at point: CGPoint) {
        dragCurrent = point

        switch mode {
        case .window:
            guard let candidate = hoveredWindow ?? pointSelectableWindow(at: point) else {
                return
            }
            finishWindow(candidate)
            return
        case .screen:
            finishDisplayContaining(point)
            return
        case .crop:
            if let rect = currentDragRect, rect.width >= 8, rect.height >= 8 {
                finish(.region(rect))
            } else {
                dragStart = nil
                dragCurrent = nil
                redrawAll()
            }
        }
    }

    func updateHover(at point: CGPoint) {
        hoveredWindow = pointSelectableWindow(at: point)
        redrawAll()
    }

    func clearHover() {
        guard hoveredWindow != nil else {
            return
        }

        hoveredWindow = nil
        redrawAll()
    }

    func hoverWindow(number: Int) {
        let candidate = numberedWindowCandidates.first { $0.number == number }?.candidate
        guard hoveredWindow != candidate else {
            return
        }

        hoveredWindow = candidate
        redrawAll()
    }

    func toggleMode() {
        let modes = enabledModes
        guard let currentIndex = modes.firstIndex(of: mode) else {
            mode = .window
            return
        }

        mode = modes[(currentIndex + 1) % modes.count]
    }

    func setMode(_ mode: Mode) {
        guard enabledModes.contains(mode) else {
            return
        }

        self.mode = mode
    }

    func toggleAnnotationMode() {
        guard configuration.annotationEnabled else {
            return
        }

        focusedToolbarOption = .annotation
        annotationArmed.toggle()
        redrawAll()
    }

    func finishWindow(number: Int) {
        freezeWindowPicker()
        guard let candidate = numberedWindowCandidates.first(where: { $0.number == number })?.candidate else {
            return
        }

        finishWindow(candidate)
    }

    func appendWindowNumberDigit(_ digit: Int) {
        freezeWindowPicker()
        numberBufferResetWorkItem?.cancel()
        numberBuffer.append(String(digit))

        guard let number = Int(numberBuffer) else {
            resetNumberBuffer()
            return
        }

        let validNumbers = Set(numberedWindowCandidates.map(\.number))
        let numberString = String(number)
        let couldBePrefix = validNumbers.contains { String($0).hasPrefix(numberString) && $0 != number }

        if validNumbers.contains(number), !couldBePrefix {
            resetNumberBuffer()
            finishWindow(number: number)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            if let bufferedNumber = Int(self.numberBuffer), validNumbers.contains(bufferedNumber) {
                self.finishWindow(number: bufferedNumber)
            }
            self.resetNumberBuffer()
        }
        numberBufferResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
    }

    func handleKeyCode(_ keyCode: CGKeyCode) {
        if let digit = digit(from: keyCode), mode == .window {
            appendWindowNumberDigit(digit)
            return
        }

        switch keyCode {
        case 53:
            cancel()
        case 0:
            toggleAnnotationMode()
        case 49:
            if focusedToolbarOption == .annotation {
                toggleAnnotationMode()
            } else {
                toggleMode()
            }
        case 13:
            setMode(.window)
        case 8:
            setMode(.crop)
        case 3:
            setMode(.screen)
        case 123:
            focusToolbarOption(offset: -1)
        case 124:
            focusToolbarOption(offset: 1)
        case 125:
            moveHoveredWindow(offset: 1)
        case 126:
            moveHoveredWindow(offset: -1)
        case 36, 76:
            finishCurrentSelection(mousePoint: NSEvent.mouseLocation)
        default:
            return
        }
    }

    func handleInputEvent(_ event: CaptureOverlayInputEvent) {
        guard isActive else {
            return
        }

        switch event {
        case .keyDown(let keyCode):
            handleKeyCode(keyCode)
        case .mouseMoved(let point):
            overlayView(containing: point)?.handleGlobalMouseMoved(at: point)
        case .leftMouseDown(let point):
            let overlayView = overlayView(containing: point)
            activePointerView = overlayView
            overlayView?.handleGlobalMouseDown(at: point)
        case .leftMouseDragged(let point):
            (activePointerView ?? overlayView(containing: point))?.handleGlobalMouseDragged(at: point)
        case .leftMouseUp(let point):
            (activePointerView ?? overlayView(containing: point))?.handleGlobalMouseUp(at: point)
            activePointerView = nil
        case .scrollWheel(let point, let deltaY):
            overlayView(containing: point)?.handleGlobalScroll(at: point, deltaY: deltaY)
        case .swallow:
            return
        }
    }

    private func moveHoveredWindow(offset: Int) {
        guard mode == .window, !numberedWindowCandidates.isEmpty else {
            return
        }

        freezeWindowPicker()
        let currentIndex = hoveredWindow.flatMap { hoveredWindow in
            windowCandidates.firstIndex(of: hoveredWindow)
        } ?? (offset > 0 ? -1 : windowCandidates.count)
        let nextIndex = (currentIndex + offset + windowCandidates.count) % windowCandidates.count
        hoveredWindow = windowCandidates[nextIndex]
        ensureWindowNumberVisible(nextIndex + 1)
        redrawAll()
    }

    private func focusToolbarOption(offset: Int) {
        let options = enabledToolbarOptions
        guard let currentIndex = options.firstIndex(of: focusedToolbarOption) else {
            focusedToolbarOption = .window
            return
        }

        let nextIndex = (currentIndex + offset + options.count) % options.count
        let nextOption = options[nextIndex]
        focusedToolbarOption = nextOption
        if let mode = nextOption.mode {
            self.mode = mode
        } else {
            redrawAll()
        }
    }

    var numberedWindowCandidates: [(number: Int, candidate: WindowCandidate)] {
        windowCandidates.enumerated().map { index, candidate in
            (number: index + 1, candidate: candidate)
        }
    }

    var enabledModes: [Mode] {
        var modes: [Mode] = [.window]
        if configuration.cropEnabled {
            modes.append(.crop)
        }
        if configuration.fullScreenEnabled {
            modes.append(.screen)
        }
        return modes
    }

    var enabledToolbarOptions: [ToolbarOption] {
        var options = enabledModes.map(ToolbarOption.init(mode:))
        if configuration.annotationEnabled {
            options.append(.annotation)
        }
        return options
    }

    func finishCurrentSelection(mousePoint: CGPoint) {
        switch mode {
        case .window:
            freezeWindowPicker()
            guard let hoveredWindow else {
                return
            }
            finishWindow(hoveredWindow)
        case .screen:
            finishDisplayContaining(mousePoint)
        case .crop:
            if let rect = currentDragRect, rect.width >= 8, rect.height >= 8 {
                finish(.region(rect))
            }
        }
    }

    var currentDragRect: CGRect? {
        guard let dragStart, let dragCurrent else {
            return nil
        }

        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        ).integral
    }

    private func finishDisplayContaining(_ point: CGPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let screen else {
            cancel()
            return
        }

        finish(.display(screen.frame.integral))
    }

    private func finish(_ selection: CaptureSelection) {
        guard isActive else {
            return
        }

        closeWindows()
        completion(CaptureOverlayResult(selection: selection, shouldAnnotate: annotationArmed))
    }

    private func finishWindow(_ candidate: WindowCandidate) {
        finish(.window(candidate.frame, windowID: candidate.windowID))
    }

    private func pointSelectableWindow(at point: CGPoint) -> WindowCandidate? {
        windowCandidates.first { candidate in
            candidate.isOnScreen == true && candidate.frame.contains(point)
        }
    }

    private func updateWindowCandidates(_ candidates: [WindowCandidate], context: String) {
        guard !isWindowPickerFrozen || windowCandidates.isEmpty else {
            DebugLog.write("overlay candidates skipped context=\(context) reason=pickerFrozen")
            return
        }

        let selectableCandidates = candidates.filter(\.isLikelyUserSelectable)
        windowCandidates = Self.mergedWindowCandidates(
            existing: windowCandidates,
            incoming: selectableCandidates
        )
        reconcileHoveredWindow()
        DebugLog.write("overlay candidates context=\(context) screenCount=\(NSScreen.screens.count) rawCandidates=\(candidates.count) selectableCandidates=\(selectableCandidates.count) shownCandidates=\(windowCandidates.count)")
        redrawAll()
    }

    private static func mergedWindowCandidates(
        existing: [WindowCandidate],
        incoming: [WindowCandidate]
    ) -> [WindowCandidate] {
        let incomingByID = bestCandidatesByWindowID(incoming)
        var seenWindowIDs = Set<CGWindowID>()
        var merged = existing.map { candidate -> WindowCandidate in
            let replacement = incomingByID[candidate.windowID] ?? candidate
            seenWindowIDs.insert(replacement.windowID)
            return replacement
        }

        for candidate in incoming where !seenWindowIDs.contains(candidate.windowID) {
            seenWindowIDs.insert(candidate.windowID)
            merged.append(candidate)
        }

        return merged
    }

    private static func bestCandidatesByWindowID(_ candidates: [WindowCandidate]) -> [CGWindowID: WindowCandidate] {
        candidates.reduce(into: [CGWindowID: WindowCandidate]()) { partial, candidate in
            guard let existing = partial[candidate.windowID] else {
                partial[candidate.windowID] = candidate
                return
            }

            if candidate.selectionScore > existing.selectionScore {
                partial[candidate.windowID] = candidate
            }
        }
    }

    private func reconcileHoveredWindow() {
        guard let hoveredWindow else {
            return
        }

        self.hoveredWindow = windowCandidates.first { $0.windowID == hoveredWindow.windowID }
    }

    func freezeWindowPicker() {
        isWindowPickerFrozen = true
    }

    private func ensureWindowNumberVisible(_ number: Int) {
        windows.forEach { window in
            window.overlayView.ensureSidebarNumberVisible(number)
        }
    }

    private func closeWindows() {
        isActive = false
        inputInterceptor?.stop()
        inputInterceptor = nil
        activePointerView = nil
        numberBufferResetWorkItem?.cancel()
        numberBufferResetWorkItem = nil
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func redrawAll() {
        windows.forEach { $0.overlayView.needsDisplay = true }
    }

    private func invalidateCursorRects() {
        windows.forEach { window in
            window.invalidateCursorRects(for: window.overlayView)
        }
    }

    private func resetNumberBuffer() {
        numberBuffer = ""
        numberBufferResetWorkItem?.cancel()
        numberBufferResetWorkItem = nil
    }

    private func digit(from keyCode: CGKeyCode) -> Int? {
        switch keyCode {
        case 18:
            1
        case 19:
            2
        case 20:
            3
        case 21:
            4
        case 23:
            5
        case 22:
            6
        case 26:
            7
        case 28:
            8
        case 25:
            9
        case 29:
            0
        default:
            nil
        }
    }

    private func overlayView(containing point: CGPoint) -> CaptureOverlayView? {
        windows.first { window in
            window.frame.contains(point)
        }?.overlayView ?? windows.first?.overlayView
    }
}

final class CaptureOverlayWindow: NSWindow {
    let overlayView: CaptureOverlayView

    init(screen: NSScreen, controller: CaptureOverlayController) {
        overlayView = CaptureOverlayView(screenFrame: screen.frame, controller: controller)

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isMovable = false
        isMovableByWindowBackground = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        contentView = overlayView
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

enum CaptureOverlayInputEvent {
    case keyDown(CGKeyCode)
    case mouseMoved(CGPoint)
    case leftMouseDown(CGPoint)
    case leftMouseDragged(CGPoint)
    case leftMouseUp(CGPoint)
    case scrollWheel(CGPoint, CGFloat)
    case swallow
}

private final class CaptureOverlayInputInterceptor {
    private let handler: @MainActor (CaptureOverlayInputEvent) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping @MainActor (CaptureOverlayInputEvent) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        guard eventTap == nil else {
            return true
        }

        let eventTypes: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseDragged,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseDragged,
            .otherMouseUp,
            .mouseMoved,
            .scrollWheel
        ]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | CGEventMask(1 << type.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func dispatch(_ event: CaptureOverlayInputEvent) {
        let handler = handler
        Task { @MainActor in
            handler(event)
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let interceptor = Unmanaged<CaptureOverlayInputInterceptor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        switch type {
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            interceptor.dispatch(.keyDown(keyCode))
            return nil
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            interceptor.dispatch(.swallow)
            return nil
        case .leftMouseDown:
            interceptor.dispatch(.leftMouseDown(appKitPoint(from: event.location)))
            return nil
        case .leftMouseDragged:
            interceptor.dispatch(.leftMouseDragged(appKitPoint(from: event.location)))
            return nil
        case .leftMouseUp:
            interceptor.dispatch(.leftMouseUp(appKitPoint(from: event.location)))
            return nil
        case .mouseMoved:
            interceptor.dispatch(.mouseMoved(appKitPoint(from: event.location)))
            return nil
        case .scrollWheel:
            let deltaY = CGFloat(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            interceptor.dispatch(.scrollWheel(appKitPoint(from: event.location), deltaY))
            return nil
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap = interceptor.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static func appKitPoint(from quartzPoint: CGPoint) -> CGPoint {
        let screenFrames = NSScreen.screens.map(\.frame)
        guard let union = screenFrames.reduce(nil, { partial, frame -> CGRect? in
            guard let partial else {
                return frame
            }
            return partial.union(frame)
        }) else {
            return quartzPoint
        }

        return CGPoint(x: quartzPoint.x, y: union.maxY - quartzPoint.y)
    }
}

final class CaptureOverlayView: NSView {
    private let screenFrame: CGRect
    private weak var controller: CaptureOverlayController?
    private var trackingAreaRef: NSTrackingArea?
    private var modeRects: [CaptureOverlayController.Mode: CGRect] = [:]
    private var annotationRect = CGRect.zero
    private var sidebarPanelRect = CGRect.zero
    private var sidebarRowRects: [Int: CGRect] = [:]
    private var sidebarScrollOffset: CGFloat = 0
    private var hoveredSidebarNumber: Int?
    private var isCaptureMouseDown = false
    private var pendingSidebarNumber: Int?

    init(screenFrame: CGRect, controller: CaptureOverlayController) {
        self.screenFrame = screenFrame
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func resetCursorRects() {
        guard controller?.mode == .crop else {
            addCursorRect(bounds, cursor: .arrow)
            return
        }

        addCursorRect(bounds, cursor: .crosshair)
        if !sidebarPanelRect.isEmpty {
            addCursorRect(sidebarPanelRect, cursor: .arrow)
        }
        for rect in modeRects.values {
            addCursorRect(rect, cursor: .arrow)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.34).setFill()
        bounds.fill()

        drawScreenFrame()
        drawWindowCandidates()

        if let rect = controller?.currentDragRect {
            drawSelection(rect, strokeColor: .systemGreen, label: "Crop")
        }

        if let hovered = controller?.hoveredWindow {
            drawSelection(hovered.frame, strokeColor: .systemBlue, label: hovered.displayName)
        }

        drawWindowSidebar()
        drawModeBar()
    }

    override func mouseDown(with event: NSEvent) {
        handleGlobalMouseDown(at: globalPoint(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        handleGlobalMouseDragged(at: globalPoint(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        handleGlobalMouseUp(at: globalPoint(from: event))
    }

    override func mouseMoved(with event: NSEvent) {
        handleGlobalMouseMoved(at: globalPoint(from: event))
    }

    override func scrollWheel(with event: NSEvent) {
        let globalPoint = globalPoint(from: event)
        if handleGlobalScroll(at: globalPoint, deltaY: event.scrollingDeltaY) {
            return
        }

        super.scrollWheel(with: event)
    }

    func handleGlobalMouseDown(at globalPoint: CGPoint) {
        isCaptureMouseDown = false
        pendingSidebarNumber = nil

        let localPoint = localPoint(from: globalPoint)
        if let mode = modeRects.first(where: { $0.value.contains(localPoint) })?.key {
            controller?.setMode(mode)
            return
        }

        if annotationRect.contains(localPoint) {
            controller?.toggleAnnotationMode()
            return
        }

        if let number = sidebarRowRects.first(where: { $0.value.contains(localPoint) })?.key {
            controller?.freezeWindowPicker()
            pendingSidebarNumber = number
            isCaptureMouseDown = true
            return
        }

        if sidebarPanelRect.contains(localPoint) {
            return
        }

        if controller?.mode == .window {
            controller?.freezeWindowPicker()
            isCaptureMouseDown = true
            return
        }

        if controller?.mode == .screen {
            isCaptureMouseDown = true
            return
        }

        isCaptureMouseDown = controller?.mode == .crop
        controller?.beginDrag(at: globalPoint)
    }

    func handleGlobalMouseDragged(at globalPoint: CGPoint) {
        guard isCaptureMouseDown else {
            return
        }

        controller?.updateDrag(to: globalPoint)
    }

    func handleGlobalMouseUp(at globalPoint: CGPoint) {
        guard isCaptureMouseDown else {
            return
        }

        isCaptureMouseDown = false
        if let pendingSidebarNumber {
            self.pendingSidebarNumber = nil
            controller?.finishWindow(number: pendingSidebarNumber)
            return
        }

        controller?.finishDrag(at: globalPoint)
    }

    func handleGlobalMouseMoved(at globalPoint: CGPoint) {
        let localPoint = localPoint(from: globalPoint)
        let rowNumber = sidebarRowRects.first(where: { $0.value.contains(localPoint) })?.key
        if hoveredSidebarNumber != rowNumber {
            hoveredSidebarNumber = rowNumber
            needsDisplay = true
        }

        if let rowNumber {
            controller?.hoverWindow(number: rowNumber)
            return
        }

        if sidebarPanelRect.contains(localPoint) {
            controller?.clearHover()
            return
        }

        controller?.updateHover(at: globalPoint)
    }

    @discardableResult
    func handleGlobalScroll(at globalPoint: CGPoint, deltaY: CGFloat) -> Bool {
        guard sidebarPanelRect.contains(localPoint(from: globalPoint)) else {
            return false
        }

        let maximumOffset = maxSidebarScrollOffset()
        sidebarScrollOffset = min(max(sidebarScrollOffset + deltaY, 0), maximumOffset)
        needsDisplay = true
        return true
    }

    func ensureSidebarNumberVisible(_ number: Int) {
        guard let controller,
              let index = controller.numberedWindowCandidates.firstIndex(where: { $0.number == number }) else {
            return
        }

        let panel = currentSidebarRect()
        let clipRect = sidebarRowsClipRect(in: panel)
        guard clipRect.height > 0 else {
            return
        }

        let rowHeight = sidebarRowHeight
        let contentTop = panel.maxY - sidebarHeaderHeight
        let rowMinY = contentTop - CGFloat(index + 1) * rowHeight + sidebarScrollOffset + 3
        let rowMaxY = rowMinY + rowHeight - 6

        if rowMinY < clipRect.minY {
            sidebarScrollOffset += clipRect.minY - rowMinY
        } else if rowMaxY > clipRect.maxY {
            sidebarScrollOffset -= rowMaxY - clipRect.maxY
        }

        sidebarPanelRect = panel
        sidebarScrollOffset = min(max(sidebarScrollOffset, 0), maxSidebarScrollOffset(panel: panel, rowCount: controller.numberedWindowCandidates.count))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        controller?.handleKeyCode(event.keyCode)
    }

    private func globalPoint(from event: NSEvent) -> CGPoint {
        let local = event.locationInWindow
        return CGPoint(
            x: screenFrame.minX + local.x,
            y: screenFrame.minY + local.y
        )
    }

    private func localPoint(from globalPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: globalPoint.x - screenFrame.minX,
            y: globalPoint.y - screenFrame.minY
        )
    }

    private func localRect(from globalRect: CGRect) -> CGRect {
        CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: globalRect.minY - screenFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    private func drawScreenFrame() {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 10, dy: 10))
        path.lineWidth = 2
        NSColor.white.withAlphaComponent(0.28).setStroke()
        path.stroke()

        let label = "Full Screen"
        drawBadge(label, symbolName: "display", at: CGPoint(x: 20, y: 20), tint: .white)
    }

    private func drawWindowCandidates() {
        guard let controller else {
            return
        }

        for numberedCandidate in controller.numberedWindowCandidates {
            let candidate = numberedCandidate.candidate
            guard candidate.isOnScreen == true else {
                continue
            }

            let local = localRect(from: candidate.frame).intersection(bounds)
            guard !local.isNull, local.width > 32, local.height > 32 else {
                continue
            }

            let path = NSBezierPath(roundedRect: local, xRadius: 7, yRadius: 7)
            path.lineWidth = 1.5
            NSColor.white.withAlphaComponent(0.32).setStroke()
            path.stroke()

            if controller.mode == .window {
                let badgePoint = CGPoint(x: local.minX + 8, y: local.maxY - 31)
                drawNumberedBadge(
                    number: numberedCandidate.number,
                    title: candidate.shortName,
                    at: badgePoint,
                    tint: .white
                )
            }
        }
    }

    private func drawWindowSidebar() {
        guard let controller else {
            return
        }

        let candidates = controller.numberedWindowCandidates
        sidebarRowRects.removeAll()
        sidebarPanelRect = currentSidebarRect()
        sidebarScrollOffset = min(sidebarScrollOffset, maxSidebarScrollOffset())

        let panel = sidebarPanelRect
        NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8).stroke()

        drawSidebarHeader(in: panel, count: candidates.count)
        drawSidebarRows(candidates, in: panel)
        drawSidebarFooter(in: panel)
        drawSidebarScrollIndicator(in: panel, rowCount: candidates.count)
    }

    private func drawSidebarHeader(in panel: CGRect, count: Int) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        NSAttributedString(string: "Windows", attributes: titleAttributes)
            .draw(at: CGPoint(x: panel.minX + 14, y: panel.maxY - 28))

        let detail: String
        if count == 0 {
            detail = "No windows found - press C or F"
        } else if count == 1 {
            detail = "1 window - press its number"
        } else {
            detail = "\(count) windows - press number or click"
        }
        NSAttributedString(string: detail, attributes: subtitleAttributes)
            .draw(at: CGPoint(x: panel.minX + 14, y: panel.maxY - 47))

        NSColor.separatorColor.withAlphaComponent(0.48).setStroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: panel.minX + 10, y: panel.maxY - 57))
        divider.line(to: CGPoint(x: panel.maxX - 10, y: panel.maxY - 57))
        divider.stroke()
    }

    private func drawSidebarRows(
        _ candidates: [(number: Int, candidate: WindowCandidate)],
        in panel: CGRect
    ) {
        let clipRect = sidebarRowsClipRect(in: panel)
        guard clipRect.height > 0 else {
            return
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: clipRect).addClip()

        let rowHeight = sidebarRowHeight
        let contentTop = panel.maxY - sidebarHeaderHeight
        for (index, numberedCandidate) in candidates.enumerated() {
            let rowY = contentTop - CGFloat(index + 1) * rowHeight + sidebarScrollOffset
            let rowRect = CGRect(
                x: panel.minX + 8,
                y: rowY + 3,
                width: panel.width - 16,
                height: rowHeight - 6
            )

            guard rowRect.intersects(clipRect) else {
                continue
            }

            sidebarRowRects[numberedCandidate.number] = rowRect
            drawSidebarRow(
                number: numberedCandidate.number,
                candidate: numberedCandidate.candidate,
                rect: rowRect
            )
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawSidebarRow(number: Int, candidate: WindowCandidate, rect: CGRect) {
        let isHovered = hoveredSidebarNumber == number
        let isWindowHovered = controller?.hoveredWindow == candidate
        let background = isHovered || isWindowHovered
            ? NSColor.controlAccentColor.withAlphaComponent(0.82)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.72)
        background.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let numberRect = CGRect(x: rect.minX + 7, y: rect.midY - 10, width: 28, height: 20)
        NSColor.labelColor.withAlphaComponent(isHovered || isWindowHovered ? 0.98 : 0.90).setFill()
        NSBezierPath(roundedRect: numberRect, xRadius: 5, yRadius: 5).fill()

        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.windowBackgroundColor
        ]
        let numberString = NSAttributedString(string: "\(number)", attributes: numberAttributes)
        let numberSize = numberString.size()
        numberString.draw(at: CGPoint(x: numberRect.midX - numberSize.width / 2, y: numberRect.midY - numberSize.height / 2))

        let titleRect = CGRect(x: numberRect.maxX + 8, y: rect.midY + 1, width: rect.maxX - numberRect.maxX - 18, height: 14)
        let subtitleRect = CGRect(x: titleRect.minX, y: rect.midY - 15, width: titleRect.width, height: 13)

        drawTruncated(candidate.listTitle, in: titleRect, font: .systemFont(ofSize: 12, weight: .semibold), color: isHovered || isWindowHovered ? .white : .labelColor)
        drawTruncated(candidate.listSubtitle, in: subtitleRect, font: .systemFont(ofSize: 11, weight: .regular), color: isHovered || isWindowHovered ? NSColor.white.withAlphaComponent(0.74) : .secondaryLabelColor)
    }

    private func drawSidebarFooter(in panel: CGRect) {
        NSColor.separatorColor.withAlphaComponent(0.48).setStroke()
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: panel.minX + 10, y: panel.minY + sidebarFooterHeight))
        divider.line(to: CGPoint(x: panel.maxX - 10, y: panel.minY + sidebarFooterHeight))
        divider.stroke()

        let footer = controllerFooterText()
        drawTruncated(
            footer,
            in: CGRect(x: panel.minX + 14, y: panel.minY + 9, width: panel.width - 28, height: 13),
            font: .systemFont(ofSize: 11, weight: .medium),
            color: NSColor.secondaryLabelColor
        )
    }

    private func controllerFooterText() -> String {
        guard let controller else {
            return "Esc cancel"
        }

        var parts = ["W window"]
        if controller.enabledModes.contains(.crop) {
            parts.append("C crop")
        }
        if controller.enabledModes.contains(.screen) {
            parts.append("F full")
        }
        if controller.enabledToolbarOptions.contains(.annotation) {
            parts.append("A annotate")
        }
        parts.append("Esc cancel")
        return parts.joined(separator: "   ")
    }

    private func drawSidebarScrollIndicator(in panel: CGRect, rowCount: Int) {
        let maximumOffset = maxSidebarScrollOffset(panel: panel, rowCount: rowCount)
        guard maximumOffset > 1 else {
            return
        }

        let clipRect = sidebarRowsClipRect(in: panel)
        let contentHeight = CGFloat(rowCount) * sidebarRowHeight
        let thumbHeight = max(28, clipRect.height * clipRect.height / contentHeight)
        let availableTravel = clipRect.height - thumbHeight
        let progress = maximumOffset == 0 ? 0 : sidebarScrollOffset / maximumOffset
        let thumbY = clipRect.maxY - thumbHeight - availableTravel * progress
        let thumbRect = CGRect(x: panel.maxX - 7, y: thumbY, width: 3, height: thumbHeight)

        NSColor.secondaryLabelColor.withAlphaComponent(0.58).setFill()
        NSBezierPath(roundedRect: thumbRect, xRadius: 2, yRadius: 2).fill()
    }

    private var sidebarHeaderHeight: CGFloat {
        58
    }

    private var sidebarFooterHeight: CGFloat {
        32
    }

    private var sidebarRowHeight: CGFloat {
        40
    }

    private func currentSidebarRect() -> CGRect {
        let width = min(max(bounds.width * 0.27, 320), min(380, bounds.width - 32))
        let topPadding: CGFloat = 58
        let bottomPadding: CGFloat = 58
        let availableHeight = max(220, bounds.height - topPadding - bottomPadding)
        return CGRect(x: 16, y: bottomPadding, width: width, height: availableHeight)
    }

    private func sidebarRowsClipRect(in panel: CGRect) -> CGRect {
        CGRect(
            x: panel.minX + 8,
            y: panel.minY + sidebarFooterHeight,
            width: panel.width - 16,
            height: panel.height - sidebarHeaderHeight - sidebarFooterHeight
        )
    }

    private func maxSidebarScrollOffset() -> CGFloat {
        maxSidebarScrollOffset(panel: sidebarPanelRect, rowCount: controller?.numberedWindowCandidates.count ?? 0)
    }

    private func maxSidebarScrollOffset(panel: CGRect, rowCount: Int) -> CGFloat {
        guard !panel.isEmpty else {
            return 0
        }

        let visibleHeight = sidebarRowsClipRect(in: panel).height
        let contentHeight = CGFloat(rowCount) * sidebarRowHeight
        return max(0, contentHeight - visibleHeight)
    }

    private func drawTruncated(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(with: rect, options: [.usesLineFragmentOrigin])
    }

    private func drawSelection(_ globalRect: CGRect, strokeColor: NSColor = .systemGreen, label: String? = nil) {
        let local = localRect(from: globalRect).intersection(bounds)
        guard !local.isNull, local.width > 0, local.height > 0 else {
            return
        }

        if let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.compositingOperation = .clear
            NSColor.clear.setFill()
            NSBezierPath(roundedRect: local, xRadius: 7, yRadius: 7).fill()
            context.restoreGraphicsState()
        }

        let path = NSBezierPath(roundedRect: local, xRadius: 7, yRadius: 7)
        path.lineWidth = 3
        strokeColor.setStroke()
        path.stroke()

        if let label {
            drawBadge(label, symbolName: "checkmark.circle", at: CGPoint(x: local.minX + 8, y: local.maxY - 31), tint: strokeColor)
        }
    }

    private func drawModeBar() {
        guard let controller else {
            return
        }

        modeRects.removeAll()
        annotationRect = .zero

        var chipTitles = controller.enabledModes.map { mode in
            "\(mode.title) \(mode.shortcut)"
        }
        if controller.enabledToolbarOptions.contains(.annotation) {
            chipTitles.append("Annotate A")
        }
        chipTitles.append("Esc")

        let chipWidths = chipTitles.map { chipWidth(for: $0) }
        let totalChipWidth = chipWidths.reduce(0, +) + CGFloat(max(chipTitles.count - 1, 0)) * 8
        let toolbarWidth = min(bounds.width - 24, totalChipWidth + 20)
        let toolbar = CGRect(
            x: 12,
            y: bounds.height - 58,
            width: toolbarWidth,
            height: 44
        )

        NSColor.windowBackgroundColor.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: toolbar, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        NSBezierPath(roundedRect: toolbar, xRadius: 9, yRadius: 9).stroke()

        var x = toolbar.minX + 10
        let y = toolbar.midY - 17
        for mode in controller.enabledModes {
            let isActive = controller.mode == mode
            let isFocused = controller.focusedToolbarOption == CaptureOverlayController.ToolbarOption(mode: mode)
            let title = "\(mode.title) \(mode.shortcut)"
            let rect = drawChip(
                title,
                symbolName: mode.symbolName,
                at: CGPoint(x: x, y: y),
                isActive: isActive,
                isFocused: isFocused
            )
            modeRects[mode] = rect
            x = rect.maxX + 8
        }

        if controller.enabledToolbarOptions.contains(.annotation) {
            annotationRect = drawChip(
                "Annotate A",
                symbolName: "pencil.and.outline",
                at: CGPoint(x: x, y: y),
                isActive: controller.annotationArmed,
                isFocused: controller.focusedToolbarOption == .annotation,
                activeTint: .systemOrange
            )
            x = annotationRect.maxX + 8
        }

        drawChip("Esc", symbolName: "xmark", at: CGPoint(x: x, y: y), isActive: false)
    }

    private func chipWidth(for title: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]
        return NSAttributedString(string: title, attributes: attributes).size().width + 46
    }

    @discardableResult
    private func drawChip(
        _ title: String,
        symbolName: String,
        at point: CGPoint,
        isActive: Bool,
        isFocused: Bool = false,
        activeTint: NSColor = .systemBlue
    ) -> CGRect {
        let symbolSize = CGSize(width: 16, height: 16)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let textSize = text.size()
        let rect = CGRect(x: point.x, y: point.y, width: textSize.width + 46, height: 34)

        (isActive ? activeTint.withAlphaComponent(0.92) : NSColor.controlBackgroundColor.withAlphaComponent(0.82)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        NSColor.white.withAlphaComponent(isActive ? 0.26 : 0.16).setStroke()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).stroke()
        if isFocused {
            NSColor.white.withAlphaComponent(0.88).setStroke()
            let focusPath = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5)
            focusPath.lineWidth = 2
            focusPath.stroke()
        }

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            symbol.lockFocus()
            NSColor.white.set()
            let symbolRect = CGRect(origin: CGPoint(x: 0, y: 0), size: symbolSize)
            symbol.draw(in: symbolRect)
            symbol.unlockFocus()
            symbol.draw(in: CGRect(x: rect.minX + 10, y: rect.midY - 8, width: 16, height: 16))
        }
        text.draw(at: CGPoint(x: rect.minX + 32, y: rect.midY - textSize.height / 2))

        return rect
    }

    private func drawBadge(_ title: String, symbolName: String, at point: CGPoint, tint: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let string = NSAttributedString(string: title, attributes: attributes)
        let size = string.size()
        let rect = CGRect(x: point.x, y: point.y, width: min(size.width + 36, 220), height: 24)

        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        tint.withAlphaComponent(0.95).setFill()
        NSBezierPath(ovalIn: CGRect(x: rect.minX + 7, y: rect.midY - 4, width: 8, height: 8)).fill()
        string.draw(at: CGPoint(x: rect.minX + 22, y: rect.midY - size.height / 2))
    }

    private func drawNumberedBadge(number: Int, title: String, at point: CGPoint, tint: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let string = NSAttributedString(string: title, attributes: attributes)
        let size = string.size()
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let numberString = NSAttributedString(string: "\(number)", attributes: numberAttributes)
        let numberSize = numberString.size()
        let numberPillWidth = max(numberSize.width + 8, 18)
        let rect = CGRect(x: point.x, y: point.y, width: min(size.width + numberPillWidth + 21, 260), height: 24)

        NSColor.black.withAlphaComponent(0.68).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        tint.withAlphaComponent(0.95).setFill()
        let numberRect = CGRect(x: rect.minX + 5, y: rect.midY - 8, width: numberPillWidth, height: 16)
        NSBezierPath(roundedRect: numberRect, xRadius: 4, yRadius: 4).fill()

        numberString.draw(at: CGPoint(x: numberRect.midX - numberSize.width / 2, y: rect.midY - 6.5))
        let titleRect = CGRect(
            x: numberRect.maxX + 6,
            y: rect.midY - size.height / 2,
            width: rect.maxX - numberRect.maxX - 11,
            height: size.height
        )
        string.draw(with: titleRect, options: [.usesLineFragmentOrigin])
    }
}

private extension CaptureOverlayController.Mode {
    var shortcut: String {
        switch self {
        case .window:
            "W"
        case .crop:
            "C"
        case .screen:
            "F"
        }
    }
}

private extension WindowCandidate {
    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        return shortName
    }

    var shortName: String {
        ownerName ?? "Window"
    }

    var listTitle: String {
        if let ownerName, !ownerName.isEmpty {
            return ownerName
        }
        return "Window"
    }

    var listSubtitle: String {
        guard let title, !title.isEmpty else {
            return "Untitled window"
        }

        return title
    }
}
