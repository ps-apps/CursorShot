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

@MainActor
final class PasteboardInjector {
    func copyToClipboard(payload: InjectionPayload) throws {
        try write(payload: payload, to: .general)
    }

    func paste(payload: InjectionPayload, origin: OriginContext) throws {
        try write(payload: payload, to: .general)
        try pasteFromClipboard(origin: origin)
    }

    func pasteFromClipboard(origin: OriginContext) throws {
        guard let targetApp = NSRunningApplication(processIdentifier: origin.pid) else {
            throw PasteboardInjectorError.targetUnavailable
        }

        guard targetApp.activate(options: [.activateAllWindows]) else {
            throw PasteboardInjectorError.targetActivationFailed(origin.appName)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            self.restoreFocusIfPossible(origin)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self.postCommandV()
            }
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

    private func restoreFocusIfPossible(_ origin: OriginContext) {
        guard let focusedElement = origin.focusedElement else {
            return
        }

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            focusedElement
        )
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
}
