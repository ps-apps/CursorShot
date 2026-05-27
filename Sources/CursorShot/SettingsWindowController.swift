import AppKit
import CursorShotCore
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
    private static let contentSize = NSSize(width: 620, height: 680)

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
            window.minSize = Self.contentSize
            window.maxSize = Self.contentSize
            window.setContentSize(Self.contentSize)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            DebugLog.write("settings window shown existing reason=\(reason)")
            return
        }

        let contentView = SettingsView(settings: settings, reason: reason)
        let hostingView = NSHostingView(rootView: contentView)
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "CursorShot Settings"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.minSize = Self.contentSize
        newWindow.maxSize = Self.contentSize
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
    @State private var isShowingHelp = false
    @State private var recordingHotKeyRole: HotKeyRole?
    @State private var hotKeyRecorderMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !PermissionCenter.hasAllPermissions {
                        permissionSetupBlock
                    }

                    capturePanel
                    permissionsPanel
                    storagePanel
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 620, height: 680, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            CursorShotLogoView()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("CursorShot")
                        .font(.system(size: 23, weight: .semibold))
                    InfoButton("A local capture utility for saving screenshots and pasting the right reference back into the app where you started.")
                }
                StatusPill(
                    title: PermissionCenter.hasAllPermissions ? "Ready" : "Setup",
                    symbolName: PermissionCenter.hasAllPermissions ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: PermissionCenter.hasAllPermissions ? .green : .orange
                )
            }

            Spacer()

            Button {
                isShowingHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 18, weight: .medium))
            .accessibilityLabel("Help")
            .help("How CursorShot works")
            .popover(isPresented: $isShowingHelp, arrowEdge: .bottom) {
                SettingsHelpView()
                    .frame(width: 380)
                    .padding(18)
            }
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 26)
            Text("Permissions needed")
                .font(.system(size: 13, weight: .semibold))
            InfoButton("Grant Screen Recording for capture and Accessibility for returning focus and pasting back.")
            Spacer()
            Button {
                startPermissionSetup(preferredTarget: .accessibility)
            } label: {
                Label("Request", systemImage: "hand.tap")
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var permissionSetupBlock: some View {
        VStack(spacing: 6) {
            permissionBanner
            PermissionInlineGuideRow()
        }
    }

    private var capturePanel: some View {
        SettingsPanel(title: "Capture", symbolName: "viewfinder") {
            VStack(alignment: .leading, spacing: 8) {
                ShortcutSettingRow(
                    title: "Open Picker",
                    symbolName: "viewfinder",
                    helpText: "Opens the full capture picker with window, crop, full-screen, and annotation options.",
                    hotKey: settings.defaultCaptureHotKey,
                    isRecording: recordingHotKeyRole == .defaultCapture,
                    changeAction: { startHotKeyRecording(for: .defaultCapture) },
                    resetAction: { resetHotKey(for: .defaultCapture) }
                )
                ShortcutSettingRow(
                    title: "Cmd-Tab Quick",
                    symbolName: "rectangle.2.swap",
                    helpText: "Captures the next app in the Cmd-Tab order, then pastes back into the app where you started.",
                    hotKey: settings.cmdTabQuickCaptureHotKey,
                    isRecording: recordingHotKeyRole == .cmdTabQuickCapture,
                    changeAction: { startHotKeyRecording(for: .cmdTabQuickCapture) },
                    resetAction: { resetHotKey(for: .cmdTabQuickCapture) }
                )
                ShortcutSettingRow(
                    title: "Current-Space Quick",
                    symbolName: "bolt",
                    helpText: "Captures the selected target on the current Space without opening the picker.",
                    hotKey: settings.currentSpaceQuickCaptureHotKey,
                    isRecording: recordingHotKeyRole == .currentSpaceQuickCapture,
                    changeAction: { startHotKeyRecording(for: .currentSpaceQuickCapture) },
                    resetAction: { resetHotKey(for: .currentSpaceQuickCapture) }
                )

                if let recordingHotKeyRole {
                    HotKeyRecorderView(
                        onRecord: { finishHotKeyRecording($0, for: recordingHotKeyRole) },
                        onCancel: cancelHotKeyRecording,
                        onInvalid: { hotKeyRecorderMessage = $0 }
                    )
                    .frame(height: 36)
                    .padding(.leading, SettingsRowMetrics.contentIndent)
                }

                if let hotKeyRecorderMessage {
                    Text(hotKeyRecorderMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, SettingsRowMetrics.contentIndent)
                }
            }

            InlineSettingsRow(
                title: "Quick target",
                symbolName: "bolt",
                helpText: "Current-space quick capture can target the active app or the top other visible app on the current Space."
            ) {
                Picker("", selection: $settings.currentSpaceCaptureTargetRaw) {
                    Text("Current App").tag(CurrentSpaceCaptureTarget.currentApp.rawValue)
                    Text("Top App").tag(CurrentSpaceCaptureTarget.topApp.rawValue)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
                .frame(width: SettingsRowMetrics.menuControlWidth, alignment: .trailing)
            }

            InlineSettingsRow(
                title: "Delivery",
                symbolName: "arrowshape.turn.up.right",
                helpText: "Smart sends an image to rich editors and a shell-safe file path to terminal-style apps."
            ) {
                Picker("", selection: $settings.injectionModeRaw) {
                    Text("Smart").tag(InjectionMode.smart.rawValue)
                    Text("Path").tag(InjectionMode.alwaysPath.rawValue)
                    Text("Image").tag(InjectionMode.alwaysImage.rawValue)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .labelsHidden()
                .frame(width: SettingsRowMetrics.menuControlWidth, alignment: .trailing)
            }

            SettingsRow(
                title: "Modes",
                symbolName: "square.dashed",
                helpText: "Window capture is always available. Disable Crop, Full Screen, or Annotate to remove them from the picker."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ModeToggleRow(title: "Window", symbolName: "macwindow", isOn: .constant(true), locked: true)
                    ModeToggleRow(title: "Crop", symbolName: "crop", isOn: $settings.cropModeEnabled)
                    ModeToggleRow(title: "Full Screen", symbolName: "display", isOn: $settings.fullScreenModeEnabled)
                    ModeToggleRow(title: "Annotate", symbolName: "pencil.and.outline", isOn: $settings.annotationModeEnabled)
                }
                .frame(maxWidth: .infinity)
            }

            InlineSettingsRow(
                title: "Feedback",
                symbolName: "speaker.wave.2",
                helpText: "Play lightweight sounds when capture and paste actions complete."
            ) {
                Toggle("", isOn: $settings.captureSoundsEnabled)
                    .toggleStyle(CompactSwitchToggleStyle())
                    .labelsHidden()
            }
        }
    }

    private var storagePanel: some View {
        SettingsPanel(title: "Storage", symbolName: "folder") {
            SettingsRow(
                title: "Directory",
                symbolName: "externaldrive",
                helpText: "CursorShot stores PNGs and JSON metadata here. The default directory is private; custom folders keep their existing folder permissions."
            ) {
                HStack(spacing: 8) {
                    TextField("", text: $settings.storageDirectory)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260, maxWidth: .infinity)

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

            SettingsRow(
                title: "Retention",
                symbolName: "clock.arrow.circlepath",
                helpText: "Older PNG and JSON capture files are removed on launch and after each new capture."
            ) {
                Stepper(value: $settings.retentionDays, in: 1...90) {
                    Text("\(settings.retentionDays) days")
                        .monospacedDigit()
                        .frame(width: 84, alignment: .leading)
                }
            }
        }
    }

    private var permissionsPanel: some View {
        SettingsPanel(title: "Permissions", symbolName: "lock.shield") {
            PermissionRow(
                title: "Screen Recording",
                helpText: "Required by macOS before CursorShot can capture windows, crops, and full displays.",
                symbolName: "rectangle.on.rectangle",
                granted: PermissionCenter.screenRecordingGranted,
                openAction: {
                    startPermissionSetup(preferredTarget: .screenRecording)
                },
                resetAction: {
                    resetPermission(.screenRecording)
                },
                refreshAction: {
                    settings.objectWillChange.send()
                }
            )

            PermissionRow(
                title: "Accessibility",
                helpText: "Required by macOS before CursorShot can return focus, restore the cursor target, and paste back.",
                symbolName: "cursorarrow.motionlines",
                granted: PermissionCenter.accessibilityGranted,
                openAction: {
                    startPermissionSetup(preferredTarget: .accessibility)
                },
                resetAction: {
                    resetPermission(.accessibility)
                },
                refreshAction: {
                    settings.objectWillChange.send()
                }
            )
        }
    }

    private func startHotKeyRecording(for role: HotKeyRole) {
        recordingHotKeyRole = role
        hotKeyRecorderMessage = "Press a shortcut for \(role.displayName), or Esc to cancel."
    }

    private func finishHotKeyRecording(_ hotKey: HotKey, for role: HotKeyRole) {
        if let conflict = settings.conflictingHotKeyAssignment(assigning: hotKey, to: role) {
            hotKeyRecorderMessage = "\(hotKey.label) is already used by \(conflict.role.displayName)."
            return
        }

        settings.assignHotKey(hotKey, to: role)
        recordingHotKeyRole = nil
        hotKeyRecorderMessage = "Saved \(hotKey.label)."
    }

    private func cancelHotKeyRecording() {
        recordingHotKeyRole = nil
        hotKeyRecorderMessage = nil
    }

    private func resetHotKey(for role: HotKeyRole) {
        settings.resetHotKey(for: role)
        recordingHotKeyRole = nil
        hotKeyRecorderMessage = "Reset \(role.displayName)."
    }

    private func resetPermission(_ target: PermissionTarget) {
        do {
            _ = try PermissionCenter.resetPermission(target)
            showAlert(
                title: "Permission Reset",
                message: "\(permissionTitle(target)) was reset. Quit and reopen CursorShot, then grant the permission again."
            )
            settings.objectWillChange.send()
        } catch {
            showAlert(title: "Permission Reset Failed", message: error.localizedDescription)
        }
    }

    private func permissionTitle(_ target: PermissionTarget) -> String {
        switch target {
        case .screenRecording:
            "Screen Recording"
        case .accessibility:
            "Accessibility"
        }
    }

    private func startPermissionSetup(preferredTarget: PermissionTarget) {
        PermissionGuideWindowController.shared.close()
        PermissionGuideWindowController.startSystemPermissionFlow(
            preferredTarget: preferredTarget,
            requestPrompts: true
        )
        settings.objectWillChange.send()
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
    let helpText: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        symbolName: String,
        helpText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbolName = symbolName
        self.helpText = helpText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: SettingsRowMetrics.spacing) {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsRowMetrics.iconWidth, height: SettingsRowMetrics.rowTitleHeight)
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .semibold))
                if let helpText {
                    InfoButton(helpText)
                }
                Spacer(minLength: 0)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, SettingsRowMetrics.contentIndent)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct InlineSettingsRow<Content: View>: View {
    let title: String
    let symbolName: String
    let helpText: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        symbolName: String,
        helpText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbolName = symbolName
        self.helpText = helpText
        self.content = content()
    }

    var body: some View {
        HStack(spacing: SettingsRowMetrics.spacing) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(width: SettingsRowMetrics.iconWidth, height: SettingsRowMetrics.rowTitleHeight)
            Text(title)
                .lineLimit(1)
                .font(.system(size: 13, weight: .semibold))
            if let helpText {
                InfoButton(helpText)
            }
            Spacer(minLength: 12)
            HStack {
                Spacer(minLength: 0)
                content
            }
            .frame(width: SettingsRowMetrics.inlineControlWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
    }
}

private enum SettingsRowMetrics {
    static let iconWidth: CGFloat = 22
    static let spacing: CGFloat = 12
    static let contentIndent: CGFloat = iconWidth + spacing
    static let controlWidth: CGFloat = 260
    static let inlineControlWidth: CGFloat = 190
    static let menuControlWidth: CGFloat = 170
    static let shortcutActionWidth: CGFloat = 246
    static let shortcutButtonWidth: CGFloat = 120
    static let shortcutChipWidth: CGFloat = 104
    static let rowTitleHeight: CGFloat = 25
}

private struct ShortcutSettingRow: View {
    let title: String
    let symbolName: String
    let helpText: String
    let hotKey: HotKey
    let isRecording: Bool
    let changeAction: () -> Void
    let resetAction: () -> Void

    var body: some View {
        HStack(spacing: SettingsRowMetrics.spacing) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(width: SettingsRowMetrics.iconWidth, height: SettingsRowMetrics.rowTitleHeight)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            InfoButton(helpText)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                ShortcutChip(isRecording ? "Recording..." : hotKey.compactLabel, tint: isRecording ? .orange : .blue)
                    .frame(width: SettingsRowMetrics.shortcutChipWidth, alignment: .trailing)

                ShortcutChangeControl(
                    title: title,
                    changeAction: changeAction,
                    resetAction: resetAction
                )
            }
            .frame(width: SettingsRowMetrics.shortcutActionWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
    }
}

private struct ShortcutChangeControl: View {
    let title: String
    let changeAction: () -> Void
    let resetAction: () -> Void

    private let resetWidth: CGFloat = 30
    private let dividerWidth: CGFloat = 1
    private let controlHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            Button {
                resetAction()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: resetWidth, height: controlHeight)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reset \(title) shortcut")
            .help("Reset shortcut")

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: dividerWidth, height: 16)

            Button {
                changeAction()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: controlHeight)
                    Text("Change")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(
                    width: SettingsRowMetrics.shortcutButtonWidth - resetWidth - dividerWidth,
                    height: controlHeight,
                    alignment: .center
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Change \(title) shortcut")
            .help("Change shortcut")
        }
        .frame(width: SettingsRowMetrics.shortcutButtonWidth, height: controlHeight)
        .background(Color(nsColor: .controlColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct PermissionRow: View {
    let title: String
    let helpText: String
    let symbolName: String
    let granted: Bool
    let openAction: () -> Void
    let resetAction: () -> Void
    let refreshAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: SettingsRowMetrics.spacing) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(width: SettingsRowMetrics.iconWidth, height: SettingsRowMetrics.rowTitleHeight)

            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                InfoButton(helpText)
            }

            Spacer(minLength: 0)

            StatusPill(
                title: granted ? "Granted" : "Missing",
                symbolName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                tint: granted ? .green : .orange
            )

            HStack(spacing: 8) {
                Button {
                    openAction()
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Open \(title) settings")
                .help("Open System Settings")

                Button {
                    resetAction()
                } label: {
                    Label("Reset", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .accessibilityLabel("Reset \(title) permission")
                .help("Reset this macOS permission entry")

                Button {
                    refreshAction()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                .controlSize(.small)
                .accessibilityLabel("Refresh \(title) permission")
                .help("Refresh permission status")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct InfoButton: View {
    let text: String
    @State private var isPresented = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(text)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 250, alignment: .leading)
                .padding(12)
        }
        .onHover { isHovering in
            isPresented = isHovering
        }
    }
}

private struct ShortcutChip: View {
    let title: String
    let tint: Color

    init(_ title: String, tint: Color = .primary) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ModeToggleRow: View {
    let title: String
    let symbolName: String
    @Binding var isOn: Bool
    var locked = false

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(CompactSwitchToggleStyle())
                .labelsHidden()
                .disabled(locked)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .help(locked ? "Window capture is always enabled." : "Show or hide \(title) in the capture picker.")
    }
}

private struct CompactSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(trackColor(isOn: configuration.isOn))
                .frame(width: 32, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 12, height: 12)
                        .padding(3)
                        .shadow(color: .black.opacity(0.16), radius: 1, x: 0, y: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }

    private func trackColor(isOn: Bool) -> Color {
        if !isEnabled {
            return Color.accentColor.opacity(isOn ? 0.45 : 0.18)
        }

        return isOn ? Color.accentColor : Color.secondary.opacity(0.26)
    }
}

private struct CursorShotLogoView: View {
    private let icon = CursorShotIconProvider.image()
    @State private var isPulsing = false

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .scaleEffect(isPulsing ? 1.025 : 0.985)
            .shadow(color: .black.opacity(isPulsing ? 0.18 : 0.1), radius: isPulsing ? 8 : 4, x: 0, y: 3)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct SettingsHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("How CursorShot works", systemImage: "questionmark.circle")
                .font(.headline)

            HelpSectionView(
                title: "Open",
                symbolName: "keyboard",
                text: "Use the Open Picker shortcut or the menu bar item to show the capture picker."
            )

            HelpSectionView(
                title: "Quick capture",
                symbolName: "bolt",
                text: "Use the quick shortcuts to capture the Cmd-Tab target or the configured current-space target without opening the picker."
            )

            HelpSectionView(
                title: "Choose",
                symbolName: "arrow.up.arrow.down",
                text: "Use Up and Down to move through visible windows, Left and Right to move across enabled tools, and Return to capture."
            )

            HelpSectionView(
                title: "Deliver",
                symbolName: "arrowshape.turn.up.right",
                text: "CursorShot saves the PNG locally, returns to the starting app, and pastes an image or file path based on your delivery setting."
            )
        }
    }
}

private struct HelpSectionView: View {
    let title: String
    let symbolName: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
