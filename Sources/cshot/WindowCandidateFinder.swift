import AppKit
import CoreGraphics
import cshotCore
import Foundation

struct WindowCandidate: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String?
    let title: String?
    let frame: CGRect
}

struct WindowCandidateFinder {
    private let converter = CoordinateConverter()

    func candidate(at point: CGPoint, excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> WindowCandidate? {
        candidates(excludingPID: excludingPID).first { candidate in
            candidate.frame.contains(point)
        }
    }

    func candidates(excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> [WindowCandidate] {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let screenFrames = NSScreen.screens.map(\.frame)

        return rawWindows.compactMap { info in
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
                frame: appKitRect
            )
        }
    }
}
