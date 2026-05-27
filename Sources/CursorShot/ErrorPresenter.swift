import AppKit
import Foundation

@MainActor
final class ErrorPresenter {
    private let statusPresenter = CaptureStatusPresenter()

    func showError(_ error: Error) {
        showMessage(error.localizedDescription)
    }

    func showMessage(_ message: String) {
        DebugLog.write("present error messageLength=\(message.count)")
        statusPresenter.show(
            message: message,
            symbolName: "exclamationmark.triangle",
            duration: 2.8
        )
    }
}
