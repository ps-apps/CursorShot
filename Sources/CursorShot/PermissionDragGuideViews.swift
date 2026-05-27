import AppKit
import SwiftUI

struct PermissionInlineGuideRow: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 10) {
            DraggableCursorShotAppIconView()
                .frame(width: 42, height: 42)
                .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)

            PermissionMiniDragAnimationView(animate: animate)
                .frame(width: 106, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text("Drag to System Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("Drop in the permission list")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

private struct PermissionMiniDragAnimationView: View {
    let animate: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let midY = proxy.size.height / 2

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
                    .foregroundStyle(.secondary.opacity(0.34))
                    .frame(width: 34, height: 34)
                    .position(x: width - 19, y: midY)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                    .position(x: animate ? width * 0.52 : width * 0.36, y: midY)
                    .opacity(animate ? 1 : 0.42)

                Image(systemName: "cursorarrow")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .position(
                        x: animate ? width - 18 : width * 0.52,
                        y: animate ? midY - 12 : midY + 12
                    )
                    .opacity(0.78)
            }
        }
    }
}

struct DraggableCursorShotAppIconView: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorShotAppIconDragSourceView {
        CursorShotAppIconDragSourceView()
    }

    func updateNSView(_ nsView: CursorShotAppIconDragSourceView, context: Context) {}
}

final class CursorShotAppIconDragSourceView: NSView, NSDraggingSource {
    private let appURL = Bundle.main.bundleURL
    private let appIcon = CursorShotIconProvider.image()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 42, height: 42)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(bounds.width, bounds.height) * 0.18
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        NSColor.controlAccentColor.withAlphaComponent(0.2).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        border.lineWidth = 1.4
        border.setLineDash([4, 3], count: 2, phase: 0)
        border.stroke()

        let iconInset = max(6, min(bounds.width, bounds.height) * 0.18)
        let iconRect = bounds.insetBy(dx: iconInset, dy: iconInset)
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
