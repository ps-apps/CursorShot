import AppKit
import CoreGraphics
import cshotCore
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

        let rawSummary = rawWindows.prefix(18).enumerated().map { index, info in
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? -1
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "nil"
            let title = info[kCGWindowName as String] as? String ?? "nil"
            let layer = info[kCGWindowLayer as String] as? Int ?? -999
            let alpha = info[kCGWindowAlpha as String] as? Double ?? -1
            let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool
            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            return "#\(index + 1){pid=\(ownerPID),owner=\(ownerName),title=\(title),id=\(windowID),layer=\(layer),alpha=\(alpha),onScreen=\(isOnscreen.map(String.init) ?? "nil")}"
        }.joined(separator: " ")
        DebugLog.write("window finder raw scope=\(scope.debugName) excludingPID=\(excludingPID) rawCount=\(rawWindows.count) screens=\(screenFrames) \(rawSummary)")

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

        let candidateSummary = candidates.prefix(18).enumerated().map { index, candidate in
            "#\(index + 1){pid=\(candidate.ownerPID),owner=\(candidate.ownerName ?? "nil"),title=\(candidate.title ?? "nil"),id=\(candidate.windowID),frame=\(candidate.frame)}"
        }.joined(separator: " ")
        DebugLog.write("window finder candidates scope=\(scope.debugName) excludingPID=\(excludingPID) count=\(candidates.count) \(candidateSummary)")
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

                let summary = candidates.prefix(18).enumerated().map { index, candidate in
                    "#\(index + 1){pid=\(candidate.ownerPID),owner=\(candidate.ownerName ?? "nil"),title=\(candidate.title ?? "nil"),id=\(candidate.windowID),onScreen=\(candidate.isOnScreen.map(String.init) ?? "nil"),frame=\(candidate.frame)}"
                }.joined(separator: " ")
                DebugLog.write("window finder SCK candidates excludingPID=\(excludingPID) count=\(candidates.count) \(summary)")
                return candidates
            } catch {
                DebugLog.write("window finder SCK failed excludingPID=\(excludingPID) error=\(error.localizedDescription)")
                return []
            }
        }

        return []
    }
}

extension WindowCandidate {
    var isLikelyUserSelectable: Bool {
        guard frame.width >= 120, frame.height >= 80 else {
            return false
        }

        if frame.height <= 72, frame.width >= 400 {
            return false
        }

        guard let ownerName, !Self.ignoredOwnerNames.contains(ownerName) else {
            return ownerName == nil
        }

        return true
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
}
