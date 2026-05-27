import AppKit
import ApplicationServices
import cshotCore
import Foundation
import ScreenCaptureKit

enum CaptureCoordinatorError: LocalizedError {
    case noCurrentSpaceCaptureWindow(CurrentSpaceCaptureTarget)
    case noCmdTabNextApp
    case noCmdTabNextAppWindow

    var errorDescription: String? {
        switch self {
        case .noCurrentSpaceCaptureWindow(let target):
            switch target {
            case .currentApp:
                "No app window was found for the current app."
            case .topApp:
                "No other top app window was found on the current Space."
            }
        case .noCmdTabNextApp:
            "No next app was found in the Cmd-Tab rotation."
        case .noCmdTabNextAppWindow:
            "No visible window was found for the next Cmd-Tab app."
        }
    }
}

@MainActor
final class CaptureCoordinator {
    private let settings: SettingsStore
    private let activationTracker: ApplicationActivationTracker
    private let originReader = OriginContextReader()
    private let coordinateConverter = CoordinateConverter()
    private let windowFinder = WindowCandidateFinder()
    private let topWindowSelector = TopWindowCaptureSelector()
    private let captureService = ScreenCaptureService()
    private let imageWriter = ImageWriter()
    private let metadataWriter = CaptureMetadataWriter()
    private let annotationEditor = AnnotationEditorController()
    private let annotationRenderer = AnnotationRenderer()
    private let classifier = TargetProfileClassifier()
    private let payloadFactory = InjectionPayloadFactory()
    private let injector = PasteboardInjector()
    private let statusPresenter = CaptureStatusPresenter()
    private let soundPlayer = FeedbackSoundPlayer()
    private let errorPresenter: ErrorPresenter

    private var overlayController: CaptureOverlayController?
    private var isProcessingCapture = false

    init(
        settings: SettingsStore,
        activationTracker: ApplicationActivationTracker,
        errorPresenter: ErrorPresenter
    ) {
        self.settings = settings
        self.activationTracker = activationTracker
        self.errorPresenter = errorPresenter
    }

    func captureNow() {
        DebugLog.write("captureNow requested")
        guard canStartCapture(), hasRequiredPermissions() else {
            return
        }

        let origin = originReader.capture()
        DebugLog.write("captureNow origin=\(debugSummary(origin))")
        let pasteboardSnapshot = PasteboardSnapshot.capture()
        hidecshotWindowsBeforeCapture()

        let controller = CaptureOverlayController { [weak self] result in
            guard let self else {
                return
            }

            self.overlayController = nil

            guard let result else {
                return
            }

            self.isProcessingCapture = true
            Task { @MainActor in
                await self.finishCapture(
                    result: result,
                    origin: origin,
                    pasteboardSnapshot: pasteboardSnapshot,
                    delivery: .animatedHandoff
                )
            }
        }

        overlayController = controller
        controller.show()
    }

    func captureCurrentSpaceImmediateScreenshot() {
        DebugLog.write("current-space immediate requested")
        guard canStartCapture(), hasRequiredPermissions() else {
            return
        }

        let origin = originReader.capture()
        DebugLog.write("current-space origin=\(debugSummary(origin)) target=\(settings.currentSpaceCaptureTarget.rawValue)")
        activationTracker.markCurrent(pid: origin.pid)
        let pasteboardSnapshot = PasteboardSnapshot.capture()
        let target = settings.currentSpaceCaptureTarget
        let candidates = windowFinder.candidates(scope: .onScreen)
        logCandidates(candidates, context: "current-space on-screen")
        var selection = currentSpaceSelection(
            origin: origin,
            target: target,
            candidates: topWindowCandidates(from: candidates)
        )
        if selection == nil, target == .currentApp {
            DebugLog.write("current-space current-app falling back to AX window lookup pid=\(origin.pid)")
            selection = accessibilityWindowSelection(ownerPID: origin.pid)
        }

        guard let selection else {
            DebugLog.write("current-space no selection target=\(target.rawValue) mouse=(\(origin.mouseLocation.x),\(origin.mouseLocation.y))")
            pasteboardSnapshot.restore()
            errorPresenter.showError(CaptureCoordinatorError.noCurrentSpaceCaptureWindow(target))
            return
        }

        DebugLog.write("current-space selected \(debugSummary(selection))")
        isProcessingCapture = true
        Task { @MainActor in
            await self.finishCapture(
                result: CaptureOverlayResult(selection: selection, shouldAnnotate: false),
                origin: origin,
                pasteboardSnapshot: pasteboardSnapshot,
                delivery: .immediatePaste
            )
        }
    }

    func captureCmdTabImmediateScreenshot() {
        DebugLog.write("cmd-tab immediate requested")
        guard canStartCapture(), hasRequiredPermissions() else {
            return
        }

        let origin = originReader.capture()
        DebugLog.write("cmd-tab origin=\(debugSummary(origin))")
        activationTracker.markCurrent(pid: origin.pid)
        let pasteboardSnapshot = PasteboardSnapshot.capture()

        let preferredNextAppPIDs = activationTracker.preferredNextOwnerPIDs(after: origin.pid)
        guard !preferredNextAppPIDs.isEmpty else {
            DebugLog.write("cmd-tab no next app after origin pid=\(origin.pid)")
            pasteboardSnapshot.restore()
            errorPresenter.showError(CaptureCoordinatorError.noCmdTabNextApp)
            return
        }

        DebugLog.write("cmd-tab preferred next pids=\(preferredNextAppPIDs)")
        isProcessingCapture = true
        Task { @MainActor in
            do {
                let selection = try await self.resolveCmdTabNextAppSelection(preferredOwnerPIDs: preferredNextAppPIDs)
                await self.finishCapture(
                    result: CaptureOverlayResult(selection: selection, shouldAnnotate: false),
                    origin: origin,
                    pasteboardSnapshot: pasteboardSnapshot,
                    delivery: .cmdTabImmediatePaste
                )
            } catch {
                self.isProcessingCapture = false
                pasteboardSnapshot.restore()
                self.errorPresenter.showError(error)
            }
        }
    }

    private enum CaptureDelivery {
        case animatedHandoff
        case immediatePaste
        case cmdTabImmediatePaste
    }

    private func canStartCapture() -> Bool {
        guard overlayController == nil, !isProcessingCapture else {
            DebugLog.write("capture ignored: overlayActive=\(overlayController != nil) isProcessing=\(isProcessingCapture)")
            return false
        }

        return true
    }

    private func hasRequiredPermissions() -> Bool {
        guard PermissionCenter.screenRecordingGranted else {
            DebugLog.write("permission missing: screen recording")
            PermissionGuideWindowController.shared.show(preferredTarget: .screenRecording, requestPrompts: true)
            errorPresenter.showMessage(
                "Screen Recording permission is required. Use the cshot Permissions helper to enable or drag the app into System Settings."
            )
            return false
        }

        guard PermissionCenter.accessibilityGranted else {
            DebugLog.write("permission missing: accessibility")
            PermissionGuideWindowController.shared.show(preferredTarget: .accessibility, requestPrompts: true)
            errorPresenter.showMessage(
                "Accessibility permission is required so cshot can paste back. Use the cshot Permissions helper to enable or drag the app into System Settings."
            )
            return false
        }

        return true
    }

    private func hidecshotWindowsBeforeCapture() {
        DebugLog.write("hiding cshot windows count=\(NSApp.windows.count)")
        for window in NSApp.windows where !(window is CaptureOverlayWindow) {
            window.orderOut(nil)
        }
    }

    private func currentSpaceSelection(
        origin: OriginContext,
        target: CurrentSpaceCaptureTarget,
        candidates: [TopWindowCaptureCandidate]
    ) -> CaptureSelection? {
        switch target {
        case .currentApp:
            DebugLog.write("current-space selecting current-app pid=\(origin.pid)")
            return topWindowSelector.selection(for: origin.pid, target: .currentApp, candidates: candidates)
        case .topApp:
            DebugLog.write("current-space selecting top-app excluding origin pid=\(origin.pid)")
            return topWindowSelector.selection(for: origin.pid, target: .topApp, candidates: candidates)
        }
    }

    private func resolveCmdTabNextAppSelection(preferredOwnerPIDs: [pid_t]) async throws -> CaptureSelection {
        var lastError: Error?
        for ownerPID in preferredOwnerPIDs {
            do {
                return try await resolveCmdTabNextAppSelection(ownerPID: ownerPID)
            } catch {
                DebugLog.write("cmd-tab candidate failed pid=\(ownerPID) error=\(error.localizedDescription)")
                lastError = error
            }
        }

        throw lastError ?? CaptureCoordinatorError.noCmdTabNextAppWindow
    }

    private func resolveCmdTabNextAppSelection(ownerPID: pid_t) async throws -> CaptureSelection {
        guard let targetApp = NSRunningApplication(processIdentifier: ownerPID) else {
            DebugLog.write("cmd-tab target no longer running pid=\(ownerPID)")
            throw CaptureCoordinatorError.noCmdTabNextApp
        }

        targetApp.unhide()
        let activated = targetApp.activate(options: [.activateAllWindows])
        DebugLog.write("cmd-tab activate pid=\(ownerPID) app=\(targetApp.localizedName ?? "nil") bundle=\(targetApp.bundleIdentifier ?? "nil") activated=\(activated)")
        await waitForActivation(ownerPID: ownerPID)

        let onScreenCandidates = windowFinder.candidates(scope: .onScreen)
        logCandidates(onScreenCandidates, context: "cmd-tab on-screen after activation")

        if let selection = firstSelectableSelection(ownerPID: ownerPID, candidates: onScreenCandidates) {
            DebugLog.write("cmd-tab selected on-screen \(debugSummary(selection))")
            return selection
        }

        if let screenCaptureKitSelection = await screenCaptureKitWindowSelection(ownerPID: ownerPID) {
            DebugLog.write("cmd-tab selected ScreenCaptureKit \(debugSummary(screenCaptureKitSelection))")
            return screenCaptureKitSelection
        }

        let allCandidates = windowFinder.candidates(scope: .all)
        logCandidates(allCandidates, context: "cmd-tab all-windows fallback")
        if let fallbackSelection = bestSelectableSelection(ownerPID: ownerPID, candidates: allCandidates) {
            DebugLog.write("cmd-tab selected all-windows fallback \(debugSummary(fallbackSelection))")
            return fallbackSelection
        }

        if let axSelection = accessibilityWindowSelection(ownerPID: ownerPID) {
            DebugLog.write("cmd-tab selected AX fallback \(debugSummary(axSelection))")
            return axSelection
        }

        DebugLog.write("cmd-tab no visible/all/AX window for pid=\(ownerPID)")
        throw CaptureCoordinatorError.noCmdTabNextAppWindow
    }

    private func firstSelectableSelection(ownerPID: pid_t, candidates: [WindowCandidate]) -> CaptureSelection? {
        guard let candidate = candidates.first(where: { candidate in
            candidate.ownerPID == ownerPID && candidate.isLikelyUserSelectable
        }) else {
            DebugLog.write("first selectable selection none ownerPID=\(ownerPID)")
            return nil
        }

        DebugLog.write("first selectable selection ownerPID=\(ownerPID) candidate=\(debugSummary(candidate))")
        return .window(candidate.frame, windowID: candidate.windowID)
    }

    private func bestSelectableSelection(ownerPID: pid_t, candidates: [WindowCandidate]) -> CaptureSelection? {
        let ownerCandidates = candidates.filter { candidate in
            candidate.ownerPID == ownerPID
        }
        let selectableCandidates = ownerCandidates
            .filter(\.isLikelyUserSelectable)
            .sorted { lhs, rhs in
                lhs.selectionScore > rhs.selectionScore
            }

        let ownerSummary = ownerCandidates.prefix(12).map(debugSummary).joined(separator: " ")
        let selectableSummary = selectableCandidates.prefix(12).map(debugSummary).joined(separator: " ")
        DebugLog.write("best selectable ownerPID=\(ownerPID) ownerCount=\(ownerCandidates.count) selectableCount=\(selectableCandidates.count) owners=\(ownerSummary) selectable=\(selectableSummary)")

        guard let candidate = selectableCandidates.first else {
            return nil
        }

        return .window(candidate.frame, windowID: candidate.windowID)
    }

    private func screenCaptureKitWindowSelection(ownerPID: pid_t) async -> CaptureSelection? {
        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: false
                )
                let windows = content.windows.filter { window in
                    window.owningApplication?.processID == ownerPID && window.windowLayer == 0
                }
                let selectableWindows = windows
                    .filter { window in
                        isLikelySelectableWindowFrame(window.frame)
                    }
                    .sorted { lhs, rhs in
                        screenCaptureKitScore(lhs) > screenCaptureKitScore(rhs)
                    }

                let windowSummary = windows.prefix(16).map(screenCaptureKitSummary).joined(separator: " ")
                let selectableSummary = selectableWindows.prefix(16).map(screenCaptureKitSummary).joined(separator: " ")
                DebugLog.write("SCK windows ownerPID=\(ownerPID) count=\(windows.count) selectable=\(selectableWindows.count) windows=\(windowSummary) selectableWindows=\(selectableSummary)")

                guard let selectedWindow = selectableWindows.first else {
                    return nil
                }

                let rect = coordinateConverter.appKitRect(
                    fromQuartzRect: selectedWindow.frame,
                    screenFrames: NSScreen.screens.map(\.frame)
                ).integral
                return .window(rect, windowID: selectedWindow.windowID)
            } catch {
                DebugLog.write("SCK windows failed ownerPID=\(ownerPID) error=\(error.localizedDescription)")
                return nil
            }
        }

        return nil
    }

    @available(macOS 14.0, *)
    private func screenCaptureKitScore(_ window: SCWindow) -> CGFloat {
        var score = window.frame.width * window.frame.height
        if window.isActive {
            score += 2_000_000
        }
        if window.isOnScreen {
            score += 1_000_000
        }
        if window.title?.isEmpty == false {
            score += 500_000
        }
        return score
    }

    @available(macOS 14.0, *)
    private func screenCaptureKitSummary(_ window: SCWindow) -> String {
        "id=\(window.windowID),pid=\(window.owningApplication?.processID ?? -1),app=\(window.owningApplication?.applicationName ?? "nil"),title=\(window.title ?? "nil"),layer=\(window.windowLayer),active=\(window.isActive),onScreen=\(window.isOnScreen),frame=\(debugSummary(window.frame))"
    }

    private func isLikelySelectableWindowFrame(_ frame: CGRect) -> Bool {
        guard frame.width >= 120, frame.height >= 80 else {
            return false
        }

        if frame.height <= 72, frame.width >= 400 {
            return false
        }

        return true
    }

    private func waitForActivation(ownerPID: pid_t) async {
        for attempt in 1...9 {
            let frontmost = NSWorkspace.shared.frontmostApplication
            DebugLog.write("cmd-tab activation poll attempt=\(attempt) targetPID=\(ownerPID) frontmost=\(debugSummary(frontmost))")
            if frontmost?.processIdentifier == ownerPID {
                return
            }

            try? await Task.sleep(nanoseconds: 140_000_000)
        }
    }

    private func accessibilityWindowSelection(ownerPID: pid_t) -> CaptureSelection? {
        guard PermissionCenter.accessibilityGranted else {
            DebugLog.write("AX fallback skipped: accessibility permission missing pid=\(ownerPID)")
            return nil
        }

        let appElement = AXUIElementCreateApplication(ownerPID)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &value
        )

        guard result == .success, let windows = value as? [AXUIElement] else {
            DebugLog.write("AX fallback no windows pid=\(ownerPID) result=\(result.rawValue)")
            return nil
        }

        DebugLog.write("AX fallback windows pid=\(ownerPID) count=\(windows.count)")
        let screenFrames = NSScreen.screens.map(\.frame)
        for (index, window) in windows.enumerated() {
            let title = axStringAttribute(kAXTitleAttribute, from: window) ?? "nil"
            let minimized = axBoolAttribute(kAXMinimizedAttribute, from: window) ?? false
            let position = axPointAttribute(kAXPositionAttribute, from: window)
            let size = axSizeAttribute(kAXSizeAttribute, from: window)
            DebugLog.write("AX fallback window #\(index + 1) pid=\(ownerPID) title=\(title) minimized=\(minimized) position=\(position.map { String(describing: $0) } ?? "nil") size=\(size.map { String(describing: $0) } ?? "nil")")

            guard !minimized, let position, let size, size.width >= 24, size.height >= 24 else {
                continue
            }

            let quartzRect = CGRect(origin: position, size: size)
            let appKitRect = coordinateConverter.appKitRect(
                fromQuartzRect: quartzRect,
                screenFrames: screenFrames
            ).integral
            guard appKitRect.width >= 24, appKitRect.height >= 24 else {
                continue
            }

            return .window(appKitRect, windowID: nil)
        }

        return nil
    }

    private func axStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func axBoolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? Bool
    }

    private func axPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func axSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func finishCapture(
        result: CaptureOverlayResult,
        origin: OriginContext,
        pasteboardSnapshot: PasteboardSnapshot,
        delivery: CaptureDelivery
    ) async {
        defer {
            isProcessingCapture = false
        }

        do {
            DebugLog.write("finishCapture start selection=\(debugSummary(result.selection)) delivery=\(delivery)")
            let storage = CaptureStorage(
                directory: URL(fileURLWithPath: settings.effectiveStorageDirectory, isDirectory: true)
            )
            try storage.prepareDirectory()
            _ = try storage.cleanup(olderThanDays: settings.retentionDays)

            let id = UUID()
            let urls = storage.urls(for: id)

            try await Task.sleep(nanoseconds: 90_000_000)
            let capturedImage = try await captureService.capture(selection: result.selection)
            DebugLog.write("finishCapture captured image width=\(capturedImage.width) height=\(capturedImage.height)")
            playCaptureSoundIfNeeded()
            let annotationResult = try await resolveAnnotationResult(
                image: capturedImage,
                shouldAnnotate: result.shouldAnnotate
            )
            guard let annotationResult else {
                pasteboardSnapshot.restore()
                return
            }
            try imageWriter.writePNG(annotationResult.image, to: urls.image)

            let artifact = CaptureArtifact(
                id: id,
                imageURL: urls.image,
                metadataURL: urls.metadata,
                width: annotationResult.image.width,
                height: annotationResult.image.height,
                origin: origin,
                selection: result.selection,
                annotation: annotationResult.metadata
            )

            try metadataWriter.write(CaptureMetadata(artifact: artifact), to: urls.metadata)
            DebugLog.write("finishCapture wrote image=\(urls.image.path) metadata=\(urls.metadata.path)")

            let targetProfile = classifier.classify(
                bundleId: origin.bundleId,
                appName: origin.appName
            )
            let payload = payloadFactory.payload(
                for: artifact,
                targetProfile: targetProfile,
                mode: settings.injectionMode
            )

            try deliver(
                payload: payload,
                origin: origin,
                sourceRect: result.selection.rect,
                delivery: delivery
            )
            DebugLog.write("finishCapture delivered payload=\(debugSummary(payload))")
        } catch {
            DebugLog.write("finishCapture error=\(error.localizedDescription)")
            pasteboardSnapshot.restore()
            errorPresenter.showError(error)
        }
    }

    private struct ResolvedAnnotationResult {
        let image: CGImage
        let metadata: AnnotationSessionMetadata?
    }

    private func resolveAnnotationResult(
        image: CGImage,
        shouldAnnotate: Bool
    ) async throws -> ResolvedAnnotationResult? {
        guard shouldAnnotate else {
            return ResolvedAnnotationResult(image: image, metadata: nil)
        }

        switch await annotationEditor.edit(image: image) {
        case .committed(let workingImage, let elements):
            let renderedImage = try annotationRenderer.render(image: workingImage, annotations: elements)
            return ResolvedAnnotationResult(
                image: renderedImage,
                metadata: AnnotationSessionMetadata(mode: .annotated, elements: elements)
            )
        case .cancelled:
            return nil
        }
    }

    private func canInjectBack(to origin: OriginContext) -> Bool {
        origin.pid > 0
    }

    private func deliver(
        payload: InjectionPayload,
        origin: OriginContext,
        sourceRect: CGRect,
        delivery: CaptureDelivery
    ) throws {
        switch delivery {
        case .animatedHandoff:
            try deliverWithHandoff(payload: payload, origin: origin, sourceRect: sourceRect)
        case .immediatePaste:
            try deliverImmediately(payload: payload, origin: origin, restoreMode: .activateOrigin)
        case .cmdTabImmediatePaste:
            try deliverImmediately(payload: payload, origin: origin, restoreMode: .commandTabBackThenActivateOrigin)
        }
    }

    private func deliverWithHandoff(
        payload: InjectionPayload,
        origin: OriginContext,
        sourceRect: CGRect
    ) throws {
        DebugLog.write("deliverWithHandoff origin=\(debugSummary(origin)) payload=\(debugSummary(payload))")
        if canInjectBack(to: origin) {
            do {
                try injector.copyToClipboard(payload: payload)
                statusPresenter.showHandoff(
                    from: sourceRect,
                    to: origin.mouseLocation,
                    message: handoffStatusMessage(payload: payload),
                    symbolName: pasteStatusSymbol(payload: payload),
                    imageURL: handoffImageURL(payload: payload)
                ) { [weak self] in
                    self?.pastePreparedPayload(origin: origin, payload: payload)
                }
            } catch PasteboardInjectorError.targetUnavailable {
                showCopiedStatus(payload: payload)
                try injector.copyToClipboard(payload: payload)
            }
        } else {
            showCopiedStatus(payload: payload)
            try injector.copyToClipboard(payload: payload)
        }
    }

    private func deliverImmediately(
        payload: InjectionPayload,
        origin: OriginContext,
        restoreMode: PasteRestoreMode
    ) throws {
        DebugLog.write("deliverImmediately origin=\(debugSummary(origin)) payload=\(debugSummary(payload)) restoreMode=\(restoreMode)")
        try injector.copyToClipboard(payload: payload)

        guard canInjectBack(to: origin) else {
            DebugLog.write("deliverImmediately cannot inject, copied only")
            showCopiedStatus(payload: payload)
            return
        }

        do {
            try injector.pasteFromClipboard(origin: origin, restoreMode: restoreMode)
        } catch PasteboardInjectorError.targetUnavailable, PasteboardInjectorError.targetActivationFailed {
            DebugLog.write("deliverImmediately paste target unavailable/activation failed")
            showCopiedStatus(payload: payload)
        }
    }

    private func pastePreparedPayload(origin: OriginContext, payload: InjectionPayload) {
        DebugLog.write("pastePreparedPayload origin=\(debugSummary(origin)) payload=\(debugSummary(payload))")
        do {
            try injector.pasteFromClipboard(origin: origin)
        } catch PasteboardInjectorError.targetUnavailable, PasteboardInjectorError.targetActivationFailed {
            DebugLog.write("pastePreparedPayload target unavailable/activation failed")
            showCopiedStatus(payload: payload)
        } catch {
            DebugLog.write("pastePreparedPayload error=\(error.localizedDescription)")
            errorPresenter.showError(error)
        }
    }

    private func handoffStatusMessage(payload: InjectionPayload) -> String {
        switch payload {
        case .text:
            return "Paste path"
        case .image:
            return "Paste image"
        }
    }

    private func pasteStatusSymbol(payload: InjectionPayload) -> String {
        switch payload {
        case .text:
            return "terminal"
        case .image:
            return "photo.on.rectangle"
        }
    }

    private func handoffImageURL(payload: InjectionPayload) -> URL? {
        if case .image(let imageURL, _) = payload {
            return imageURL
        }

        return nil
    }

    private func showCopiedStatus(payload: InjectionPayload) {
        statusPresenter.show(
            message: copyStatusMessage(payload: payload),
            symbolName: "doc.on.clipboard",
            duration: 1.1
        )
    }

    private func copyStatusMessage(payload: InjectionPayload) -> String {
        switch payload {
        case .text:
            return "Copied path"
        case .image:
            return "Copied image"
        }
    }

    private func topWindowCandidates(from candidates: [WindowCandidate]) -> [TopWindowCaptureCandidate] {
        candidates.map { candidate in
            TopWindowCaptureCandidate(
                frame: candidate.frame,
                windowID: candidate.windowID,
                ownerPID: candidate.ownerPID
            )
        }
    }

    private func logCandidates(_ candidates: [WindowCandidate], context: String) {
        let summary = candidates.prefix(12).enumerated().map { index, candidate in
            "#\(index + 1){pid=\(candidate.ownerPID),owner=\(candidate.ownerName ?? "nil"),title=\(candidate.title ?? "nil"),windowID=\(candidate.windowID),frame=\(debugSummary(candidate.frame))}"
        }.joined(separator: " ")

        DebugLog.write("candidates context='\(context)' count=\(candidates.count) \(summary)")
    }

    private func debugSummary(_ origin: OriginContext) -> String {
        "pid=\(origin.pid) app=\(origin.appName ?? "nil") bundle=\(origin.bundleId ?? "nil") title=\(origin.windowTitle ?? "nil") mouse=(\(origin.mouseLocation.x),\(origin.mouseLocation.y)) hasFocus=\(origin.focusedElement != nil) selectedRange=\(origin.selectedRange.map { "\($0.location):\($0.length)" } ?? "nil")"
    }

    private func debugSummary(_ payload: InjectionPayload) -> String {
        switch payload {
        case .text(let text):
            return "text(\(text.count) chars)"
        case .image(let url, let fallbackText):
            return "image(url=\(url.path), fallback=\(fallbackText.count) chars)"
        }
    }

    private func debugSummary(_ selection: CaptureSelection) -> String {
        let windowID: String
        if case .window(_, let capturedWindowID) = selection {
            windowID = capturedWindowID.map(String.init) ?? "nil"
        } else {
            windowID = "nil"
        }

        return "kind=\(selection.kind) rect=\(debugSummary(selection.rect)) windowID=\(windowID)"
    }

    private func debugSummary(_ rect: CGRect) -> String {
        "(\(rect.origin.x),\(rect.origin.y),\(rect.width),\(rect.height))"
    }

    private func debugSummary(_ candidate: WindowCandidate) -> String {
        "{pid=\(candidate.ownerPID),owner=\(candidate.ownerName ?? "nil"),title=\(candidate.title ?? "nil"),windowID=\(candidate.windowID),frame=\(debugSummary(candidate.frame)),onScreen=\(candidate.isOnScreen.map(String.init) ?? "nil"),score=\(candidate.selectionScore)}"
    }

    private func debugSummary(_ app: NSRunningApplication?) -> String {
        guard let app else {
            return "nil"
        }

        return "pid=\(app.processIdentifier) app=\(app.localizedName ?? "nil") bundle=\(app.bundleIdentifier ?? "nil") active=\(app.isActive) hidden=\(app.isHidden)"
    }

    private func playCaptureSoundIfNeeded() {
        guard settings.captureSoundsEnabled else {
            return
        }

        soundPlayer.playCapture()
    }
}
