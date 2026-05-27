import AppKit
import ApplicationServices
import cshotCore
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
        restoreMode: PasteRestoreMode = .activateOrigin
    ) throws {
        DebugLog.write("pasteFromClipboard start origin=\(origin.debugSummary) restoreMode=\(restoreMode)")
        guard let targetApp = NSRunningApplication(processIdentifier: origin.pid) else {
            DebugLog.write("pasteFromClipboard target unavailable pid=\(origin.pid)")
            throw PasteboardInjectorError.targetUnavailable
        }

        switch restoreMode {
        case .activateOrigin:
            try activateOriginApp(targetApp, origin: origin)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self.waitForFrontmostAndPaste(origin, attempt: 1)
            }
        case .commandTabBackThenActivateOrigin:
            DebugLog.write("pasteFromClipboard post Command-Tab restore before activation fallback")
            postCommandTab()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                self.waitForFrontmostAndPaste(
                    origin,
                    attempt: 1,
                    fallbackApp: targetApp,
                    activationFallbackAttempt: 6
                )
            }
        }
    }

    private func activateOriginApp(_ targetApp: NSRunningApplication, origin: OriginContext) throws {
        guard targetApp.activate(options: [.activateAllWindows]) else {
            DebugLog.write("pasteFromClipboard activation failed app=\(origin.appName ?? "nil") pid=\(origin.pid)")
            throw PasteboardInjectorError.targetActivationFailed(origin.appName)
        }

        DebugLog.write("pasteFromClipboard activation succeeded app=\(targetApp.localizedName ?? "nil") pid=\(targetApp.processIdentifier)")
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
        activationFallbackAttempt: Int? = nil
    ) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmost?.processIdentifier ?? 0
        DebugLog.write("paste wait frontmost attempt=\(attempt) targetPID=\(origin.pid) frontmostPID=\(frontmostPID) frontmost=\(frontmost?.localizedName ?? "nil") cursorAvailable=\(origin.selectedRange != nil)")
        guard frontmostPID == origin.pid else {
            if attempt >= 9 {
                DebugLog.write("paste abort: origin never became frontmost targetPID=\(origin.pid) finalFrontmostPID=\(frontmostPID)")
                return
            }

            if let fallbackApp, attempt == activationFallbackAttempt {
                let activated = fallbackApp.activate(options: [.activateAllWindows])
                DebugLog.write("paste wait frontmost activation fallback targetPID=\(origin.pid) activated=\(activated)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                self.waitForFrontmostAndPaste(
                    origin,
                    attempt: attempt + 1,
                    fallbackApp: fallbackApp,
                    activationFallbackAttempt: activationFallbackAttempt
                )
            }
            return
        }

        restoreFocusAndPaste(origin, attempt: 1)
    }

    private func restoreFocusAndPaste(_ origin: OriginContext, attempt: Int) {
        let cursorAvailable = origin.selectedRange != nil
        let restored = restoreFocusIfPossible(origin)
        DebugLog.write("paste focus restore attempt=\(attempt) cursorAvailable=\(cursorAvailable) restored=\(restored)")

        if cursorAvailable, !restored, attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self.restoreFocusAndPaste(origin, attempt: attempt + 1)
            }
            return
        }

        if cursorAvailable, !restored {
            DebugLog.write("paste focus restore timed out for valid cursor; posting Command-V anyway")
        } else if !cursorAvailable {
            DebugLog.write("paste cursor position unavailable; posting Command-V may produce normal macOS failure feedback")
        }

        DebugLog.write("pasteFromClipboard post Command-V")
        postCommandV()
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
        DebugLog.write("paste restore focus setResult=\(setResult.rawValue) focusedMatches=\(focusedMatches)")
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
            DebugLog.write("paste raise window skipped result=\(result.rawValue)")
            return
        }

        let window = unsafeDowncast(value, to: AXUIElement.self)
        let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        DebugLog.write("paste raise window result=\(raiseResult.rawValue)")
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
        "pid=\(pid) app=\(appName ?? "nil") bundle=\(bundleId ?? "nil") title=\(windowTitle ?? "nil") mouse=(\(mouseLocation.x),\(mouseLocation.y)) hasFocus=\(focusedElement != nil) selectedRange=\(selectedRange.map { "\($0.location):\($0.length)" } ?? "nil")"
    }
}

private extension InjectionPayload {
    var debugSummary: String {
        switch self {
        case .text(let text):
            "text(\(text.count) chars)"
        case .image(let url, let fallbackText):
            "image(url=\(url.path), fallback=\(fallbackText.count) chars)"
        }
    }
}
