@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

enum PermissionCenter {
    static let productionBundleIdentifier = "io.github.ps-org.cursorshot"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? productionBundleIdentifier
    }

    static var resetCommand: String {
        let bundleIds = permissionBundleIds.joined(separator: " ")
        return """
        pkill -x CursorShot 2>/dev/null || true
        for bundle_id in \(bundleIds); do
          tccutil reset Accessibility "$bundle_id"
          tccutil reset ScreenCapture "$bundle_id"
        done
        """
    }

    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var hasAllPermissions: Bool {
        screenRecordingGranted && accessibilityGranted
    }

    @discardableResult
    static func requestMissingPermissions() -> Bool {
        let screenGranted = screenRecordingGranted || requestScreenRecording()
        let accessibilityTrusted = accessibilityGranted || requestAccessibility()
        return screenGranted && accessibilityTrusted
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenRecordingSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func resetCursorShotPermissions() throws -> String {
        var output: [String] = []

        for bundleId in permissionBundleIds {
            for service in ["Accessibility", "ScreenCapture"] {
                let result = try runTCCReset(service: service, bundleId: bundleId)
                output.append(result)
            }
        }

        return output.joined(separator: "\n")
    }

    static func resetPermission(_ target: PermissionTarget) throws -> String {
        let service: String
        switch target {
        case .screenRecording:
            service = "ScreenCapture"
        case .accessibility:
            service = "Accessibility"
        }

        let output = try permissionBundleIds.map { bundleId in
            try runTCCReset(service: service, bundleId: bundleId)
        }
        return output.joined(separator: "\n")
    }

    private static var permissionBundleIds: [String] {
        Array(Set([bundleIdentifier, productionBundleIdentifier, "com.local.CursorShot"])).sorted()
    }

    private static func openSystemSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private static func runTCCReset(service: String, bundleId: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleId]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = [output, error].joined().trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw PermissionResetError(service: service, bundleId: bundleId, output: combined)
        }

        return combined.isEmpty ? "\(service): reset \(bundleId)" : combined
    }
}

struct PermissionResetError: LocalizedError {
    let service: String
    let bundleId: String
    let output: String

    var errorDescription: String? {
        let suffix = output.isEmpty ? "" : "\n\n\(output)"
        return "Could not reset \(service) permission for \(bundleId).\(suffix)"
    }
}
