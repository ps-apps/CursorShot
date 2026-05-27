import AppKit
import cshotCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    enum PresentationReason {
        case settings
        case permissions
    }

    private let settings: SettingsStore
    private var window: NSWindow?
    private var reason: PresentationReason = .settings
    private static let defaultContentSize = NSSize(width: 640, height: 780)
    private static let minimumContentSize = NSSize(width: 500, height: 620)

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show(reason: PresentationReason = .settings) {
        self.reason = reason
        NSApp.setActivationPolicy(.regular)

        if let window {
            if let hostingView = window.contentView as? NSHostingView<SettingsView> {
                hostingView.rootView = SettingsView(settings: settings, reason: reason)
            }
            window.minSize = Self.minimumContentSize
            if window.frame.width < Self.minimumContentSize.width || window.frame.height < Self.minimumContentSize.height {
                window.setContentSize(Self.defaultContentSize)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            DebugLog.write("settings window shown existing reason=\(reason)")
            return
        }

        let contentView = SettingsView(settings: settings, reason: reason)
        let hostingView = NSHostingView(rootView: contentView)
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "cshot Settings"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.minSize = Self.minimumContentSize
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow

        NSApp.activate()
        DebugLog.write("settings window shown new reason=\(reason)")
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let reason: SettingsWindowController.PresentationReason
    @State private var isRecordingHotKey = false
    @State private var hotKeyRecorderMessage: String?
    @State private var isRecordingImmediateCaptureHotKey = false
    @State private var immediateCaptureHotKeyRecorderMessage: String?
    @State private var isRecordingCmdTabCaptureHotKey = false
    @State private var cmdTabCaptureHotKeyRecorderMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if reason == .permissions || !PermissionCenter.hasAllPermissions {
                    permissionBanner
                }

                capturePanel
                permissionsPanel
                storagePanel
                workflowPanel
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(minWidth: 500, minHeight: 620, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("cshot")
                    .font(.system(size: 24, weight: .semibold))
                Text("Capture, save, and paste references from anywhere.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            StatusPill(
                title: PermissionCenter.hasAllPermissions ? "Ready" : "Setup",
                symbolName: PermissionCenter.hasAllPermissions ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tint: PermissionCenter.hasAllPermissions ? .green : .orange
            )
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Permissions Required")
                    .font(.headline)
                Text("Use the permission helper to enable or drag cshot into System Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                startPermissionSetup(preferredTarget: .accessibility)
            } label: {
                Label("Request", systemImage: "hand.tap")
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var capturePanel: some View {
        SettingsPanel(title: "Capture", symbolName: "viewfinder") {
            SettingsRow(title: "Hotkey", symbolName: "keyboard") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label(settings.hotKey.label, systemImage: "keyboard")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(minWidth: 188, alignment: .leading)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        Button {
                            startHotKeyRecording()
                        } label: {
                            Label(isRecordingHotKey ? "Recording" : "Record", systemImage: "record.circle")
                        }

                        Button {
                            resetHotKey()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel("Reset hotkey")
                        .help("Reset hotkey")
                    }

                    if isRecordingHotKey {
                        HotKeyRecorderView(
                            onRecord: { hotKey in
                                finishHotKeyRecording(with: hotKey)
                            },
                            onCancel: {
                                cancelHotKeyRecording()
                            },
                            onInvalid: { message in
                                hotKeyRecorderMessage = message
                            }
                        )
                        .frame(width: SettingsRowMetrics.controlWidth, height: 36)
                    }

                    if let hotKeyRecorderMessage {
                        Text(hotKeyRecorderMessage)
                            .font(.caption)
                            .foregroundStyle(isRecordingHotKey ? Color.secondary : Color.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Opens the window, crop, full-screen, and annotation picker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsRow(title: "Current Space", symbolName: "bolt") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label(settings.immediateCaptureHotKey.label, systemImage: "keyboard")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(minWidth: 188, alignment: .leading)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        Button {
                            startImmediateCaptureHotKeyRecording()
                        } label: {
                            Label(isRecordingImmediateCaptureHotKey ? "Recording" : "Record", systemImage: "record.circle")
                        }

                        Button {
                            resetImmediateCaptureHotKey()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel("Reset immediate hotkey")
                        .help("Reset immediate hotkey")
                    }

                    if isRecordingImmediateCaptureHotKey {
                        HotKeyRecorderView(
                            onRecord: { hotKey in
                                finishImmediateCaptureHotKeyRecording(with: hotKey)
                            },
                            onCancel: {
                                cancelImmediateCaptureHotKeyRecording()
                            },
                            onInvalid: { message in
                                immediateCaptureHotKeyRecorderMessage = message
                            }
                        )
                        .frame(width: SettingsRowMetrics.controlWidth, height: 36)
                    }

                    if let immediateCaptureHotKeyRecorderMessage {
                        Text(immediateCaptureHotKeyRecorderMessage)
                            .font(.caption)
                            .foregroundStyle(isRecordingImmediateCaptureHotKey ? Color.secondary : Color.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Picker("", selection: $settings.currentSpaceCaptureTargetRaw) {
                        Label("Current App", systemImage: "macwindow")
                            .tag(CurrentSpaceCaptureTarget.currentApp.rawValue)
                        Label("Top App", systemImage: "rectangle.on.rectangle")
                            .tag(CurrentSpaceCaptureTarget.topApp.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: SettingsRowMetrics.controlWidth)

                    Text("Captures either the current app or the top other visible app on this Space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsRow(title: "Cmd-Tab Next", symbolName: "square.stack.3d.up") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label(settings.cmdTabCaptureHotKey.label, systemImage: "keyboard")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(minWidth: 188, alignment: .leading)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        Button {
                            startCmdTabCaptureHotKeyRecording()
                        } label: {
                            Label(isRecordingCmdTabCaptureHotKey ? "Recording" : "Record", systemImage: "record.circle")
                        }

                        Button {
                            resetCmdTabCaptureHotKey()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel("Reset Cmd-Tab hotkey")
                        .help("Reset Cmd-Tab hotkey")
                    }

                    if isRecordingCmdTabCaptureHotKey {
                        HotKeyRecorderView(
                            onRecord: { hotKey in
                                finishCmdTabCaptureHotKeyRecording(with: hotKey)
                            },
                            onCancel: {
                                cancelCmdTabCaptureHotKeyRecording()
                            },
                            onInvalid: { message in
                                cmdTabCaptureHotKeyRecorderMessage = message
                            }
                        )
                        .frame(width: SettingsRowMetrics.controlWidth, height: 36)
                    }

                    if let cmdTabCaptureHotKeyRecorderMessage {
                        Text(cmdTabCaptureHotKeyRecorderMessage)
                            .font(.caption)
                            .foregroundStyle(isRecordingCmdTabCaptureHotKey ? Color.secondary : Color.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Activates the next app in the Cmd-Tab rotation, captures its current top window, then pastes back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsRow(title: "Injection", symbolName: "arrowshape.turn.up.right") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $settings.injectionModeRaw) {
                        Label("Smart", systemImage: "sparkles").tag(InjectionMode.smart.rawValue)
                        Label("Path", systemImage: "terminal").tag(InjectionMode.alwaysPath.rawValue)
                        Label("Image", systemImage: "photo").tag(InjectionMode.alwaysImage.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: SettingsRowMetrics.controlWidth)

                    Text("Smart copies images; terminal apps get a path.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsRow(title: "Modes", symbolName: "square.dashed") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ModePill(title: "Window", shortcut: "W", symbolName: "macwindow", tint: .blue)
                        ModePill(title: "Crop", shortcut: "C", symbolName: "crop", tint: .green)
                        ModePill(title: "Full", shortcut: "F", symbolName: "display", tint: .purple)
                    }
                    ModePill(title: "Annotate", shortcut: "A", symbolName: "pencil.and.outline", tint: .orange)
                }
            }

            SettingsRow(title: "Sounds", symbolName: "speaker.wave.2") {
                Toggle("Capture and paste feedback", isOn: $settings.captureSoundsEnabled)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var storagePanel: some View {
        SettingsPanel(title: "Storage", symbolName: "folder") {
            SettingsRow(title: "Directory", symbolName: "externaldrive") {
                HStack(spacing: 8) {
                    TextField("", text: $settings.storageDirectory)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, maxWidth: .infinity)

                    Button {
                        chooseStorageDirectory()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("Choose storage directory")
                    .help("Choose storage directory")

                    Button {
                        openStorageDirectory()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open storage directory")
                    .help("Open storage directory")
                }
            }

            SettingsRow(title: "Retention", symbolName: "clock.arrow.circlepath") {
                HStack(spacing: 12) {
                    Stepper(value: $settings.retentionDays, in: 1...90) {
                        Text("\(settings.retentionDays) days")
                            .monospacedDigit()
                            .frame(width: 84, alignment: .leading)
                    }

                    Text("Older captures are removed on launch and capture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var permissionsPanel: some View {
        SettingsPanel(title: "Permissions", symbolName: "lock.shield") {
            PermissionRow(
                title: "Screen Recording",
                subtitle: "Required for window, crop, and full-screen capture.",
                symbolName: "rectangle.on.rectangle",
                granted: PermissionCenter.screenRecordingGranted
            ) {
                startPermissionSetup(preferredTarget: .screenRecording)
            }

            PermissionRow(
                title: "Accessibility",
                subtitle: "Required to return focus and paste back.",
                symbolName: "cursorarrow.motionlines",
                granted: PermissionCenter.accessibilityGranted
            ) {
                startPermissionSetup(preferredTarget: .accessibility)
            }

            Divider()

            SettingsRow(title: "Bundle ID", symbolName: "number") {
                Text(PermissionCenter.bundleIdentifier)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            SettingsRow(title: "App Path", symbolName: "app.badge") {
                Text(Bundle.main.bundleURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsRow(title: "Actions", symbolName: "wrench.and.screwdriver") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            startPermissionSetup(preferredTarget: .accessibility)
                        } label: {
                            Label("Guide", systemImage: "hand.tap")
                        }

                        Button {
                            resetPermissions()
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            copyPermissionResetCommand()
                        } label: {
                            Label("Copy Reset", systemImage: "doc.on.doc")
                        }

                        Button {
                            settings.objectWillChange.send()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    private var workflowPanel: some View {
        SettingsPanel(title: "Workflow", symbolName: "bolt") {
            SettingsRow(title: "Default", symbolName: "1.circle") {
                Text("Trigger the default hotkey to choose a window, crop, full screen, or annotation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsRow(title: "Current Space", symbolName: "bolt") {
                Text("Trigger the current-space hotkey to capture the current or top visible app on this Space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsRow(title: "Cmd-Tab Next", symbolName: "square.stack.3d.up") {
                Text("Trigger the Cmd-Tab hotkey to capture the next app even when it lives on another Space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func startHotKeyRecording() {
        isRecordingHotKey = true
        isRecordingImmediateCaptureHotKey = false
        isRecordingCmdTabCaptureHotKey = false
        immediateCaptureHotKeyRecorderMessage = nil
        cmdTabCaptureHotKeyRecorderMessage = nil
        hotKeyRecorderMessage = "Press a shortcut with Command, Control, or Option."
    }

    private func finishHotKeyRecording(with hotKey: HotKey) {
        settings.assignHotKey(hotKey)
        isRecordingHotKey = false
        hotKeyRecorderMessage = "Saved \(hotKey.label)."
    }

    private func cancelHotKeyRecording() {
        isRecordingHotKey = false
        hotKeyRecorderMessage = nil
    }

    private func resetHotKey() {
        settings.resetHotKeyToDefault()
        isRecordingHotKey = false
        hotKeyRecorderMessage = "Reset to \(settings.hotKey.label)."
    }

    private func startImmediateCaptureHotKeyRecording() {
        isRecordingImmediateCaptureHotKey = true
        isRecordingHotKey = false
        isRecordingCmdTabCaptureHotKey = false
        hotKeyRecorderMessage = nil
        cmdTabCaptureHotKeyRecorderMessage = nil
        immediateCaptureHotKeyRecorderMessage = "Press a shortcut with Command, Control, or Option."
    }

    private func finishImmediateCaptureHotKeyRecording(with hotKey: HotKey) {
        settings.assignImmediateCaptureHotKey(hotKey)
        isRecordingImmediateCaptureHotKey = false
        immediateCaptureHotKeyRecorderMessage = "Saved \(hotKey.label)."
    }

    private func cancelImmediateCaptureHotKeyRecording() {
        isRecordingImmediateCaptureHotKey = false
        immediateCaptureHotKeyRecorderMessage = nil
    }

    private func resetImmediateCaptureHotKey() {
        settings.resetImmediateCaptureHotKeyToDefault()
        isRecordingImmediateCaptureHotKey = false
        immediateCaptureHotKeyRecorderMessage = "Reset to \(settings.immediateCaptureHotKey.label)."
    }

    private func startCmdTabCaptureHotKeyRecording() {
        isRecordingCmdTabCaptureHotKey = true
        isRecordingHotKey = false
        isRecordingImmediateCaptureHotKey = false
        hotKeyRecorderMessage = nil
        immediateCaptureHotKeyRecorderMessage = nil
        cmdTabCaptureHotKeyRecorderMessage = "Press a shortcut with Command, Control, or Option."
    }

    private func finishCmdTabCaptureHotKeyRecording(with hotKey: HotKey) {
        settings.assignCmdTabCaptureHotKey(hotKey)
        isRecordingCmdTabCaptureHotKey = false
        cmdTabCaptureHotKeyRecorderMessage = "Saved \(hotKey.label)."
    }

    private func cancelCmdTabCaptureHotKeyRecording() {
        isRecordingCmdTabCaptureHotKey = false
        cmdTabCaptureHotKeyRecorderMessage = nil
    }

    private func resetCmdTabCaptureHotKey() {
        settings.resetCmdTabCaptureHotKeyToDefault()
        isRecordingCmdTabCaptureHotKey = false
        cmdTabCaptureHotKeyRecorderMessage = "Reset to \(settings.cmdTabCaptureHotKey.label)."
    }

    private func resetPermissions() {
        do {
            let result = try PermissionCenter.resetcshotPermissions()
            showAlert(
                title: "Permissions Reset",
                message: "\(result)\n\nQuit and reopen cshot, then grant Screen Recording and Accessibility again."
            )
        } catch {
            showAlert(title: "Permission Reset Failed", message: error.localizedDescription)
        }
    }

    private func startPermissionSetup(preferredTarget: PermissionTarget) {
        PermissionGuideWindowController.shared.show(preferredTarget: preferredTarget, requestPrompts: true)
        settings.objectWillChange.send()
    }

    private func copyPermissionResetCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PermissionCenter.resetCommand, forType: .string)
    }

    private func chooseStorageDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Capture Storage"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.effectiveStorageDirectory, isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        settings.storageDirectory = url.path
    }

    private func openStorageDirectory() {
        let url = URL(fileURLWithPath: settings.effectiveStorageDirectory, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            showAlert(title: "Could Not Open Storage", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: SettingsRowMetrics.spacing) {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsRowMetrics.iconWidth, height: SettingsRowMetrics.rowTitleHeight)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: SettingsRowMetrics.spacing) {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsRowMetrics.iconWidth, height: SettingsRowMetrics.rowTitleHeight)
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, SettingsRowMetrics.contentIndent)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private enum SettingsRowMetrics {
    static let iconWidth: CGFloat = 22
    static let spacing: CGFloat = 12
    static let contentIndent: CGFloat = iconWidth + spacing
    static let controlWidth: CGFloat = 260
    static let rowTitleHeight: CGFloat = 25
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: SettingsRowMetrics.spacing) {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsRowMetrics.iconWidth, height: SettingsRowMetrics.rowTitleHeight)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    StatusPill(
                        title: granted ? "Granted" : "Missing",
                        symbolName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                        tint: granted ? .green : .orange
                    )
                    Button {
                        action()
                    } label: {
                        Label("Open Settings", systemImage: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open \(title) settings")
                    .help("Open System Settings")
                    .disabled(granted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, SettingsRowMetrics.contentIndent)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct StatusPill: View {
    let title: String
    let symbolName: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct ModePill: View {
    let title: String
    let shortcut: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
            Text(shortcut)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tint.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
