import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class CaptureStatusPresenter {
    private var window: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?

    func show(message: String, symbolName: String, duration: TimeInterval) {
        dismissWorkItem?.cancel()

        let size = CGSize(width: 286, height: 58)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 86
        )

        let statusWindow = CaptureStatusWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        statusWindow.backgroundColor = .clear
        statusWindow.isOpaque = false
        statusWindow.hasShadow = true
        statusWindow.level = .statusBar
        statusWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        statusWindow.contentView = NSHostingView(
            rootView: CaptureStatusView(message: message, symbolName: symbolName)
        )

        window?.close()
        window = statusWindow
        statusWindow.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            self?.window?.close()
            self?.window = nil
            self?.dismissWorkItem = nil
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    func showHandoff(
        from sourceRect: CGRect,
        to destination: CGPoint,
        message: String,
        symbolName: String,
        imageURL: URL?,
        completion: @escaping @MainActor () -> Void
    ) {
        dismissWorkItem?.cancel()

        let size = CGSize(width: 148, height: 92)
        let sourceCenter = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        let startFrame = frame(centeredAt: sourceCenter, size: size)
        let endFrame = frame(centeredAt: destination, size: size)

        let handoffWindow = CaptureStatusWindow(
            contentRect: startFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        handoffWindow.backgroundColor = .clear
        handoffWindow.isOpaque = false
        handoffWindow.hasShadow = true
        handoffWindow.level = .screenSaver
        handoffWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        handoffWindow.alphaValue = 0
        handoffWindow.contentView = NSHostingView(
            rootView: CaptureHandoffView(
                message: message,
                symbolName: symbolName,
                imageURL: imageURL
            )
        )

        window?.close()
        window = handoffWindow
        handoffWindow.orderFrontRegardless()

        animateHandoffFadeIn(handoffWindow, endFrame: endFrame, completion: completion)
    }

    private func animateHandoffFadeIn(
        _ handoffWindow: NSWindow,
        endFrame: CGRect,
        completion: @escaping @MainActor () -> Void
    ) {
        NSAnimationContext.beginGrouping()
        let context = NSAnimationContext.current
        context.duration = 0.12
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        context.completionHandler = { [weak self, weak handoffWindow] in
            Task { @MainActor in
                guard let self, let handoffWindow else {
                    return
                }

                self.animateHandoffMove(handoffWindow, endFrame: endFrame, completion: completion)
            }
        }
        handoffWindow.animator().alphaValue = 1
        NSAnimationContext.endGrouping()
    }

    private func animateHandoffMove(
        _ handoffWindow: NSWindow,
        endFrame: CGRect,
        completion: @escaping @MainActor () -> Void
    ) {
        NSAnimationContext.beginGrouping()
        let context = NSAnimationContext.current
        context.duration = 0.58
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.25, 1.0)
        context.completionHandler = { [weak self, weak handoffWindow] in
            Task { @MainActor in
                guard let self, let handoffWindow else {
                    return
                }

                self.animateHandoffFadeOut(handoffWindow, completion: completion)
            }
        }
        handoffWindow.animator().setFrame(endFrame, display: true)
        NSAnimationContext.endGrouping()
    }

    private func animateHandoffFadeOut(
        _ handoffWindow: NSWindow,
        completion: @escaping @MainActor () -> Void
    ) {
        NSAnimationContext.beginGrouping()
        let context = NSAnimationContext.current
        context.duration = 0.16
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        context.completionHandler = { [weak self, weak handoffWindow] in
            Task { @MainActor in
                handoffWindow?.close()
                if self?.window === handoffWindow {
                    self?.window = nil
                }
                completion()
            }
        }
        handoffWindow.animator().alphaValue = 0
        NSAnimationContext.endGrouping()
    }

    private func frame(centeredAt point: CGPoint, size: CGSize) -> CGRect {
        let center = clamped(point, for: size)
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func clamped(_ point: CGPoint, for size: CGSize) -> CGPoint {
        let frame = NSScreen.screens.first { $0.visibleFrame.insetBy(dx: -80, dy: -80).contains(point) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        return CGPoint(
            x: min(max(point.x, frame.minX + size.width / 2 + 10), frame.maxX - size.width / 2 - 10),
            y: min(max(point.y, frame.minY + size.height / 2 + 10), frame.maxY - size.height / 2 - 10)
        )
    }
}

private final class CaptureStatusWindow: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct CaptureStatusView: View {
    let message: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(width: 286, height: 58)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct CaptureHandoffView: View {
    let message: String
    let symbolName: String
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 7) {
            preview
                .frame(width: 72, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.38), lineWidth: 1)
                )

            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(width: 148, height: 92)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.accentColor
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
