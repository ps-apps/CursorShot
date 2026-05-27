import AppKit
import ApplicationServices
import CoreGraphics
import CursorShotCore
import Foundation
import ScreenCaptureKit

struct WindowCandidate: Equatable {
    enum Source: Equatable {
        case coreGraphics
        case screenCaptureKit
    }

    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String?
    let title: String?
    let frame: CGRect
    let isOnScreen: Bool?
    let source: Source
}

struct WindowCandidateFinder {
    enum Scope {
        case onScreen
        case all

        var windowListOptions: CGWindowListOption {
            switch self {
            case .onScreen:
                [.optionOnScreenOnly, .excludeDesktopElements]
            case .all:
                [.optionAll, .excludeDesktopElements]
            }
        }

        var debugName: String {
            switch self {
            case .onScreen:
                "onScreen"
            case .all:
                "all"
            }
        }
    }

    private let converter = CoordinateConverter()

    func candidate(at point: CGPoint, excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> WindowCandidate? {
        candidates(excludingPID: excludingPID).first { candidate in
            candidate.frame.contains(point)
        }
    }

    func candidates(
        excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        scope: Scope = .onScreen
    ) -> [WindowCandidate] {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            scope.windowListOptions,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            DebugLog.write("window finder raw unavailable scope=\(scope.debugName) excludingPID=\(excludingPID)")
            return []
        }

        let screenFrames = NSScreen.screens.map(\.frame)

        DebugLog.write("window finder raw scope=\(scope.debugName) excludingPID=\(excludingPID) rawCount=\(rawWindows.count) screenCount=\(screenFrames.count)")

        let candidates = rawWindows.compactMap { info -> WindowCandidate? in
            guard
                let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID != excludingPID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary
            else {
                return nil
            }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else {
                return nil
            }

            var quartzRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary as CFDictionary, &quartzRect) else {
                return nil
            }

            let appKitRect = converter.appKitRect(fromQuartzRect: quartzRect, screenFrames: screenFrames)
            guard appKitRect.width >= 24, appKitRect.height >= 24 else {
                return nil
            }

            return WindowCandidate(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                title: info[kCGWindowName as String] as? String,
                frame: appKitRect,
                isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool,
                source: .coreGraphics
            )
        }

        DebugLog.write("window finder candidates scope=\(scope.debugName) excludingPID=\(excludingPID) count=\(candidates.count)")
        return candidates
    }

    @MainActor
    func screenCaptureKitCandidates(
        excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) async -> [WindowCandidate] {
        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: false
                )
                let screenFrames = NSScreen.screens.map(\.frame)
                let candidates = content.windows.compactMap { window -> WindowCandidate? in
                    guard window.windowLayer == 0,
                          let app = window.owningApplication,
                          app.processID != excludingPID else {
                        return nil
                    }

                    let rect = converter.appKitRect(
                        fromQuartzRect: window.frame,
                        screenFrames: screenFrames
                    )
                    guard rect.width >= 24, rect.height >= 24 else {
                        return nil
                    }

                    return WindowCandidate(
                        windowID: window.windowID,
                        ownerPID: app.processID,
                        ownerName: app.applicationName,
                        title: window.title,
                        frame: rect,
                        isOnScreen: window.isOnScreen,
                        source: .screenCaptureKit
                    )
                }

                DebugLog.write("window finder SCK candidates excludingPID=\(excludingPID) count=\(candidates.count)")
                return candidates
            } catch {
                DebugLog.write("window finder SCK failed excludingPID=\(excludingPID) errorType=\(String(describing: type(of: error)))")
                return []
            }
        }

        return []
    }
}

extension WindowCandidate {
    var isLikelyUserSelectable: Bool {
        guard windowID > 0 else {
            return false
        }

        guard frame.width >= 120, frame.height >= 80 else {
            return false
        }

        if frame.height <= 72, frame.width >= 400 {
            return false
        }

        if let ownerName, Self.ignoredOwnerNames.contains(ownerName) {
            return false
        }

        guard let ownerApplication = NSRunningApplication(processIdentifier: ownerPID),
              ownerApplication.activationPolicy == .regular,
              !ownerApplication.isHidden else {
            return false
        }

        if isOnScreen == true {
            return true
        }

        if source == .screenCaptureKit {
            return title?.isEmpty == false
        }

        guard title?.isEmpty == false else {
            return false
        }

        return hasMatchingAccessibilityWindow
    }

    var selectionScore: CGFloat {
        var score = frame.width * frame.height
        if title?.isEmpty == false {
            score += 1_000_000
        }
        if isOnScreen == true {
            score += 500_000
        }
        return score
    }

    private static let ignoredOwnerNames: Set<String> = [
        "AutoFill",
        "Caffeine",
        "Control Center",
        "Control Centre",
        "CursorUIViewService",
        "Dock",
        "Notification Center",
        "Privacy & Security",
        "SystemUIServer",
        "universalAccessAuthWarn",
        "UserNotificationCenter",
        "Window Server"
    ]

    private var hasMatchingAccessibilityWindow: Bool {
        guard PermissionCenter.accessibilityGranted else {
            return false
        }

        let appElement = AXUIElementCreateApplication(ownerPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success, let windows = value as? [AXUIElement] else {
            return false
        }

        return windows.contains { window in
            guard axBoolAttribute(kAXMinimizedAttribute, from: window) != true,
                  let position = axPointAttribute(kAXPositionAttribute, from: window),
                  let size = axSizeAttribute(kAXSizeAttribute, from: window),
                  size.width >= 120,
                  size.height >= 80 else {
                return false
            }

            let rect = CoordinateConverter().appKitRect(
                fromQuartzRect: CGRect(origin: position, size: size),
                screenFrames: NSScreen.screens.map(\.frame)
            )
            return rect.approximatelyMatches(frame)
        }
    }

    private func axBoolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? Bool
    }

    private func axPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func axSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }
}

private extension CGRect {
    func approximatelyMatches(_ other: CGRect) -> Bool {
        abs(origin.x - other.origin.x) <= 8
            && abs(origin.y - other.origin.y) <= 8
            && abs(width - other.width) <= 16
            && abs(height - other.height) <= 16
    }
}
