import AppKit
import Foundation

@MainActor
final class ErrorPresenter {
    func showError(_ error: Error) {
        showMessage(error.localizedDescription)
    }

    func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "cshot"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
