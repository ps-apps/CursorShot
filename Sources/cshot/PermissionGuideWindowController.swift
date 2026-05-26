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
        if requestPrompts {
            requestMissingPermissions()
        }

        openSettings(for: preferredTarget)

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let guideWindow = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )
        guideWindow.title = "cshot Permissions"
        guideWindow.contentMinSize = CGSize(width: 420, height: 520)
        guideWindow.level = .floating
        guideWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        guideWindow.isReleasedWhenClosed = false
        guideWindow.delegate = self
        guideWindow.contentView = NSHostingView(
            rootView: PermissionGuideView(preferredTarget: preferredTarget)
        )

        position(guideWindow)
        window = guideWindow
        guideWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func requestMissingPermissions() {
        if !PermissionCenter.screenRecordingGranted {
            PermissionCenter.requestScreenRecording()
        }
        if !PermissionCenter.accessibilityGranted {
            PermissionCenter.requestAccessibility()
        }
    }

    private func openSettings(for target: PermissionTarget) {
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

private struct PermissionGuideView: View {
    let preferredTarget: PermissionTarget
    @State private var refreshToken = 0

    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 10) {
                permissionStatusRow(
                    title: "Screen Recording",
                    detail: "Required to capture windows, crops, and full displays.",
                    granted: PermissionCenter.screenRecordingGranted,
                    action: {
                        PermissionCenter.requestScreenRecording()
                        PermissionCenter.openScreenRecordingSettings()
                    }
                )

                permissionStatusRow(
                    title: "Accessibility",
                    detail: "Required to return to the original app and paste back.",
                    granted: PermissionCenter.accessibilityGranted,
                    action: {
                        PermissionCenter.requestAccessibility()
                        PermissionCenter.openAccessibilitySettings()
                    }
                )
            }

            dragSection

            HStack(spacing: 8) {
                Button {
                    PermissionCenter.requestScreenRecording()
                    PermissionCenter.openScreenRecordingSettings()
                    refreshToken += 1
                } label: {
                    Label("Screen Recording", systemImage: "rectangle.on.rectangle")
                }

                Button {
                    PermissionCenter.requestAccessibility()
                    PermissionCenter.openAccessibilitySettings()
                    refreshToken += 1
                } label: {
                    Label("Accessibility", systemImage: "cursorarrow.motionlines")
                }
            }

            HStack(spacing: 8) {
                Button {
                    resetPermissions()
                    refreshToken += 1
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Button {
                    copyResetCommand()
                } label: {
                    Label("Copy Reset Command", systemImage: "doc.on.doc")
                }

                Button {
                    refreshToken += 1
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            Text("Bundle: \(PermissionCenter.bundleIdentifier)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(Bundle.main.bundleURL.path)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(timer) { _ in
            refreshToken += 1
            if PermissionCenter.hasAllPermissions {
                PermissionGuideWindowController.shared.close()
            }
        }
        .id(refreshToken)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 42, height: 42)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Grant cshot Permissions")
                    .font(.title3.weight(.semibold))
                Text("Keep this helper open while approving cshot in System Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dragSection: some View {
        HStack(alignment: .center, spacing: 14) {
            DraggableAppIconView()
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text("Drag cshot if it does not appear")
                    .font(.headline)
                Text("Drop this app icon into the Accessibility or Screen Recording app list, then enable the switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func permissionStatusRow(
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(granted ? "Granted" : "Open") {
                action()
            }
            .disabled(granted)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func resetPermissions() {
        do {
            _ = try PermissionCenter.resetcshotPermissions()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func copyResetCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PermissionCenter.resetCommand, forType: .string)
    }
}

private struct DraggableAppIconView: NSViewRepresentable {
    func makeNSView(context: Context) -> AppIconDragSourceView {
        AppIconDragSourceView()
    }

    func updateNSView(_ nsView: AppIconDragSourceView, context: Context) {}
}

private final class AppIconDragSourceView: NSView, NSDraggingSource {
    private let appURL = Bundle.main.bundleURL
    private let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 92, height: 92)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()

        NSColor.controlAccentColor.withAlphaComponent(0.18).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        border.lineWidth = 2
        border.setLineDash([5, 4], count: 2, phase: 0)
        border.stroke()

        let iconRect = bounds.insetBy(dx: 18, dy: 18)
        appIcon.draw(in: iconRect)
    }

    override func mouseDown(with event: NSEvent) {
        let draggingItem = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let image = dragImage()
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    private func dragImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        draw(bounds)
        image.unlockFocus()
        return image
    }
}
