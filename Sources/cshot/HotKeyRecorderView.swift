import AppKit
import cshotCore
import SwiftUI

struct HotKeyRecorderView: NSViewRepresentable {
    let onRecord: (HotKey) -> Void
    let onCancel: () -> Void
    let onInvalid: (String) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        let view = HotKeyRecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        view.onInvalid = onInvalid
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel
        nsView.onInvalid = onInvalid
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class HotKeyRecorderNSView: NSView {
    var onRecord: ((HotKey) -> Void)?
    var onCancel: (() -> Void)?
    var onInvalid: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode != 53 else {
            onCancel?()
            return
        }

        let hotKey = HotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: HotKeyModifier.mask(from: event.modifierFlags),
            keyLabel: HotKeyKeyLabel.label(for: event)
        )

        guard hotKey.validationResult == .valid else {
            onInvalid?(hotKey.validationResult.userMessage)
            return
        }

        onRecord?(hotKey)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        let backgroundPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        backgroundPath.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let text = "Press shortcut..."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: max(10, (bounds.width - size.width) / 2),
            y: max(0, (bounds.height - size.height) / 2)
        )
        text.draw(at: point, withAttributes: attributes)
    }
}

private enum HotKeyKeyLabel {
    static func label(for event: NSEvent) -> String {
        if let namedKey = namedKeys[event.keyCode] {
            return namedKey
        }

        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return "Key \(event.keyCode)"
        }

        if characters == " " {
            return "Space"
        }

        let printableCharacters = characters.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }

        guard !printableCharacters.isEmpty else {
            return "Key \(event.keyCode)"
        }

        return String(String.UnicodeScalarView(printableCharacters)).uppercased()
    }

    private static let namedKeys: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        71: "Clear",
        76: "Enter",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        114: "Help",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow"
    ]
}

private extension HotKeyModifier {
    static func mask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: [HotKeyModifier] = []
        let deviceIndependentFlags = flags.intersection(.deviceIndependentFlagsMask)

        if deviceIndependentFlags.contains(.control) {
            modifiers.append(.control)
        }
        if deviceIndependentFlags.contains(.option) {
            modifiers.append(.option)
        }
        if deviceIndependentFlags.contains(.command) {
            modifiers.append(.command)
        }
        if deviceIndependentFlags.contains(.shift) {
            modifiers.append(.shift)
        }

        return HotKeyModifier.mask(modifiers)
    }
}
