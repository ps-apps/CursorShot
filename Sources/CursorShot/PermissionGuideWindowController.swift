import AppKit
import Combine
import SwiftUI

enum PermissionTarget {
    case screenRecording
    case accessibility
}

@MainActor
final class PermissionGuideWindowController: NSObject, NSWindowDelegate {
    static let shared = PermissionGuideWindowController()

    private var window: NSPanel?

    func show(preferredTarget: PermissionTarget = .accessibility, requestPrompts: Bool = true) {
        Self.startSystemPermissionFlow(preferredTarget: preferredTarget, requestPrompts: requestPrompts)

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DebugLog.write("permission guide shown existing target=\(preferredTarget)")
            return
        }

        let guideWindow = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 340, height: 78),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        guideWindow.title = "CursorShot Permissions"
        guideWindow.contentMinSize = CGSize(width: 340, height: 78)
        guideWindow.contentMaxSize = CGSize(width: 340, height: 78)
        guideWindow.level = .floating
        guideWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        guideWindow.isReleasedWhenClosed = false
        guideWindow.delegate = self
        guideWindow.contentView = NSHostingView(
            rootView: PermissionGuidePanelView()
        )

        position(guideWindow)
        window = guideWindow
        guideWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DebugLog.write("permission guide shown new target=\(preferredTarget)")
    }

    func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    static func startSystemPermissionFlow(preferredTarget: PermissionTarget, requestPrompts: Bool) {
        if requestPrompts {
            requestMissingPermissions()
        }

        openSettings(for: preferredTarget)
    }

    private static func requestMissingPermissions() {
        if !PermissionCenter.screenRecordingGranted {
            PermissionCenter.requestScreenRecording()
        }
        if !PermissionCenter.accessibilityGranted {
            PermissionCenter.requestAccessibility()
        }
    }

    private static func openSettings(for target: PermissionTarget) {
        switch target {
        case .screenRecording:
            PermissionCenter.openScreenRecordingSettings()
        case .accessibility:
            PermissionCenter.openAccessibilitySettings()
        }
    }

    private func position(_ window: NSWindow) {
        let frame = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.frame.size
        let origin = CGPoint(
            x: frame.maxX - size.width - 32,
            y: frame.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

private struct PermissionGuidePanelView: View {
    @State private var refreshToken = 0

    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        PermissionInlineGuideRow()
            .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(timer) { _ in
            refreshToken += 1
            if PermissionCenter.hasAllPermissions {
                PermissionGuideWindowController.shared.close()
            }
        }
    }
}
