import AppKit
import ApplicationServices
import CursorShotCore
import Foundation

enum PasteboardInjectorError: LocalizedError {
    case targetUnavailable
    case targetActivationFailed(String?)
    case imageDataUnavailable(URL)

    var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            "The original target app is no longer available."
        case .targetActivationFailed(let appName):
            "Could not return to \(appName ?? "the original app")."
        case .imageDataUnavailable(let url):
            "Could not read image data at \(url.path)."
        }
    }
}

enum PasteRestoreMode {
    case activateOrigin
    case commandTabBackThenActivateOrigin
}

enum PasteboardInjectionOutcome {
    case postedPasteCommand
    case copiedOnly
}

@MainActor
final class PasteboardInjector {
    func copyToClipboard(payload: InjectionPayload) throws {
        DebugLog.write("pasteboard copy payload=\(payload.debugSummary)")
        try write(payload: payload, to: .general)
    }

    func paste(payload: InjectionPayload, origin: OriginContext) throws {
        DebugLog.write("paste payload directly origin=\(origin.debugSummary) payload=\(payload.debugSummary)")
        try write(payload: payload, to: .general)
        try pasteFromClipboard(origin: origin)
    }

    func pasteFromClipboard(
        origin: OriginContext,
        restoreMode: PasteRestoreMode = .activateOrigin,
        onCompletion: (@MainActor (PasteboardInjectionOutcome) -> Void)? = nil
    ) throws {
        DebugLog.write("pasteFromClipboard start origin=\(origin.debugSummary) restoreMode=\(restoreMode)")
        guard let targetApp = NSRunningApplication(processIdentifier: origin.pid) else {
            DebugLog.write("pasteFromClipboard target unavailable pid=\(origin.pid)")
            throw PasteboardInjectorError.targetUnavailable
        }

        switch restoreMode {
        case .activateOrigin:
            requestOriginActivation(targetApp, origin: origin, context: "initial")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self.waitForFrontmostAndPaste(
                    origin,
                    attempt: 1,
                    fallbackApp: targetApp,
                    activationFallbackAttempts: [3, 6, 10],
                    onCompletion: onCompletion
                )
            }
        case .commandTabBackThenActivateOrigin:
            DebugLog.write("pasteFromClipboard post Command-Tab restore before activation fallback")
            postCommandTab()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                self.waitForFrontmostAndPaste(
                    origin,
                    attempt: 1,
                    fallbackApp: targetApp,
                    activationFallbackAttempts: [3, 6, 10],
                    onCompletion: onCompletion
                )
            }
        }
    }

    @discardableResult
    private func requestOriginActivation(
        _ targetApp: NSRunningApplication,
        origin: OriginContext,
        context: String
    ) -> Bool {
        targetApp.unhide()
        let activated = targetApp.activate(options: [.activateAllWindows])
        DebugLog.write("pasteFromClipboard activation request context=\(context) pid=\(origin.pid) activated=\(activated)")
        if !activated {
            requestWorkspaceActivation(targetApp, origin: origin, context: context)
        }
        return activated
    }

    private func requestWorkspaceActivation(
        _ targetApp: NSRunningApplication,
        origin: OriginContext,
        context: String
    ) {
        guard let bundleURL = targetApp.bundleURL else {
            DebugLog.write("pasteFromClipboard workspace activation skipped context=\(context) pid=\(origin.pid) missingBundleURL=true")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let originPID = origin.pid
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { app, error in
            DebugLog.write("pasteFromClipboard workspace activation completed context=\(context) pid=\(originPID) hasApp=\(app != nil) errorType=\(error.map { String(describing: type(of: $0)) } ?? "nil")")
        }
    }

    private func write(payload: InjectionPayload, to pasteboard: NSPasteboard) throws {
        pasteboard.clearContents()

        switch payload {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let url, let fallbackText):
            guard let data = try? Data(contentsOf: url) else {
                throw PasteboardInjectorError.imageDataUnavailable(url)
            }

            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            item.setString(url.absoluteString, forType: .fileURL)
            item.setString(fallbackText, forType: .string)
            pasteboard.writeObjects([item])
        }
    }

    private func waitForFrontmostAndPaste(
        _ origin: OriginContext,
        attempt: Int,
        fallbackApp: NSRunningApplication? = nil,
        activationFallbackAttempts: Set<Int> = [],
        onCompletion: (@MainActor (PasteboardInjectionOutcome) -> Void)?
    ) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmost?.processIdentifier ?? 0
        if attempt == 1 {
            DebugLog.write("paste wait frontmost start targetPID=\(origin.pid) frontmostPID=\(frontmostPID) focusAvailable=\(origin.focusedElement != nil)")
        }
        guard frontmostPID == origin.pid else {
            if attempt >= 14 {
                DebugLog.write("paste abort: origin never became frontmost targetPID=\(origin.pid) finalFrontmostPID=\(frontmostPID)")
                onCompletion?(.copiedOnly)
                return
            }

            if let fallbackApp, activationFallbackAttempts.contains(attempt) {
                requestOriginActivation(fallbackApp, origin: origin, context: "retry-\(attempt)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.waitForFrontmostAndPaste(
                    origin,
                    attempt: attempt + 1,
                    fallbackApp: fallbackApp,
                    activationFallbackAttempts: activationFallbackAttempts,
                    onCompletion: onCompletion
                )
            }
            return
        }

        DebugLog.write("paste frontmost ready targetPID=\(origin.pid) attempt=\(attempt)")
        restoreFocusAndPaste(origin, attempt: 1, onCompletion: onCompletion)
    }

    private func restoreFocusAndPaste(
        _ origin: OriginContext,
        attempt: Int,
        onCompletion: (@MainActor (PasteboardInjectionOutcome) -> Void)?
    ) {
        let requiresVerifiedFocus = origin.focusedElement != nil
        let restored = restoreFocusIfPossible(origin)
        if attempt == 1 {
            DebugLog.write("paste focus restore start requiresVerifiedFocus=\(requiresVerifiedFocus)")
        }

        if requiresVerifiedFocus, !restored, attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self.restoreFocusAndPaste(origin, attempt: attempt + 1, onCompletion: onCompletion)
            }
            return
        }

        if requiresVerifiedFocus, !restored {
            DebugLog.write("paste abort: focus restore timed out; leaving payload copied")
            onCompletion?(.copiedOnly)
            return
        } else if !requiresVerifiedFocus {
            DebugLog.write("paste focused element unavailable; posting Command-V into restored frontmost app")
        } else {
            DebugLog.write("paste focus ready attempt=\(attempt)")
        }

        DebugLog.write("pasteFromClipboard post Command-V")
        postCommandV()
        onCompletion?(.postedPasteCommand)
    }

    @discardableResult
    private func restoreFocusIfPossible(_ origin: OriginContext) -> Bool {
        guard let focusedElement = origin.focusedElement else {
            DebugLog.write("paste restore focus skipped: no focused element")
            return false
        }

        raiseWindowIfPossible(for: focusedElement)

        let system = AXUIElementCreateSystemWide()
        let setResult = AXUIElementSetAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            focusedElement
        )
        let focusedMatches = focusedElementMatches(focusedElement)
        return focusedMatches || setResult == .success
    }

    private func raiseWindowIfPossible(for element: AXUIElement) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXWindowAttribute as CFString,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return
        }

        let window = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private func focusedElementMatches(_ expected: AXUIElement) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            DebugLog.write("paste focused element read failed result=\(result.rawValue)")
            return false
        }

        return CFEqual(value, expected)
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCodeV: CGKeyCode = 9

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func postCommandTab() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCodeTab: CGKeyCode = 48

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)
        commandDown?.flags = .maskCommand

        let tabDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeTab, keyDown: true)
        tabDown?.flags = .maskCommand

        let tabUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeTab, keyDown: false)
        tabUp?.flags = .maskCommand

        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)

        commandDown?.post(tap: .cghidEventTap)
        tabDown?.post(tap: .cghidEventTap)
        tabUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
    }
}

private extension OriginContext {
    var debugSummary: String {
        "pid=\(pid) hasBundle=\(bundleId != nil) hasTitle=\(windowTitle != nil) hasFocus=\(focusedElement != nil) hasSelectedRange=\(selectedRange != nil)"
    }
}

private extension InjectionPayload {
    var debugSummary: String {
        switch self {
        case .text(let text):
            "text(\(text.count) chars)"
        case .image(let url, let fallbackText):
            "image(fileExt=\(url.pathExtension), fallback=\(fallbackText.count) chars)"
        }
    }
}
