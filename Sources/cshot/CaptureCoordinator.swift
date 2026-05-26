import AppKit
import cshotCore
import Foundation

@MainActor
final class CaptureCoordinator {
    private let settings: SettingsStore
    private let originReader = OriginContextReader()
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

    init(settings: SettingsStore, errorPresenter: ErrorPresenter) {
        self.settings = settings
        self.errorPresenter = errorPresenter
    }

    func captureNow() {
        guard overlayController == nil, !isProcessingCapture else {
            NSSound.beep()
            return
        }

        guard PermissionCenter.screenRecordingGranted else {
            PermissionGuideWindowController.shared.show(preferredTarget: .screenRecording, requestPrompts: true)
            errorPresenter.showMessage(
                "Screen Recording permission is required. Use the cshot Permissions helper to enable or drag the app into System Settings."
            )
            return
        }

        guard PermissionCenter.accessibilityGranted else {
            PermissionGuideWindowController.shared.show(preferredTarget: .accessibility, requestPrompts: true)
            errorPresenter.showMessage(
                "Accessibility permission is required so cshot can paste back. Use the cshot Permissions helper to enable or drag the app into System Settings."
            )
            return
        }

        let origin = originReader.capture()
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
                await self.finishCapture(result: result, origin: origin, pasteboardSnapshot: pasteboardSnapshot)
            }
        }

        overlayController = controller
        controller.show()
    }

    private func hidecshotWindowsBeforeCapture() {
        for window in NSApp.windows where !(window is CaptureOverlayWindow) {
            window.orderOut(nil)
        }
    }

    private func finishCapture(
        result: CaptureOverlayResult,
        origin: OriginContext,
        pasteboardSnapshot: PasteboardSnapshot
    ) async {
        defer {
            isProcessingCapture = false
        }

        do {
            let storage = CaptureStorage(
                directory: URL(fileURLWithPath: settings.effectiveStorageDirectory, isDirectory: true)
            )
            try storage.prepareDirectory()
            _ = try storage.cleanup(olderThanDays: settings.retentionDays)

            let id = UUID()
            let urls = storage.urls(for: id)

            try await Task.sleep(nanoseconds: 90_000_000)
            let capturedImage = try await captureService.capture(selection: result.selection)
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

            let targetProfile = classifier.classify(
                bundleId: origin.bundleId,
                appName: origin.appName
            )
            let payload = payloadFactory.payload(
                for: artifact,
                targetProfile: targetProfile,
                mode: settings.injectionMode
            )

            if canInjectBack(to: origin) {
                do {
                    try injector.copyToClipboard(payload: payload)
                    playHandoffSoundIfNeeded()
                    statusPresenter.showHandoff(
                        from: result.selection.rect,
                        to: origin.mouseLocation,
                        message: handoffStatusMessage(payload: payload),
                        symbolName: pasteStatusSymbol(payload: payload),
                        imageURL: handoffImageURL(payload: payload)
                    ) { [weak self] in
                        self?.playPasteSoundIfNeeded()
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
        } catch {
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

    private func pastePreparedPayload(origin: OriginContext, payload: InjectionPayload) {
        do {
            try injector.pasteFromClipboard(origin: origin)
        } catch PasteboardInjectorError.targetUnavailable, PasteboardInjectorError.targetActivationFailed {
            showCopiedStatus(payload: payload)
        } catch {
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

    private func playCaptureSoundIfNeeded() {
        guard settings.captureSoundsEnabled else {
            return
        }

        soundPlayer.playCapture()
    }

    private func playHandoffSoundIfNeeded() {
        guard settings.captureSoundsEnabled else {
            return
        }

        soundPlayer.playHandoff()
    }

    private func playPasteSoundIfNeeded() {
        guard settings.captureSoundsEnabled else {
            return
        }

        soundPlayer.playPaste()
    }
}
