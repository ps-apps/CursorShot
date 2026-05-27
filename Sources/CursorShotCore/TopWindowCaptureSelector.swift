import CoreGraphics
import Foundation

public enum CurrentSpaceCaptureTarget: String, Codable, CaseIterable, Sendable {
    case currentApp
    case topApp
}

public struct TopWindowCaptureCandidate: Equatable, Sendable {
    public let frame: CGRect
    public let windowID: CGWindowID
    public let ownerPID: pid_t

    public init(frame: CGRect, windowID: CGWindowID, ownerPID: pid_t) {
        self.frame = frame
        self.windowID = windowID
        self.ownerPID = ownerPID
    }
}

public struct TopWindowCaptureSelector: Sendable {
    public init() {}

    public func selection(
        at point: CGPoint,
        candidates: [TopWindowCaptureCandidate]
    ) -> CaptureSelection? {
        candidates.first { candidate in
            candidate.frame.contains(point)
        }.map { candidate in
            .window(candidate.frame, windowID: candidate.windowID)
        }
    }

    public func selection(
        for ownerPID: pid_t,
        target: CurrentSpaceCaptureTarget,
        candidates: [TopWindowCaptureCandidate]
    ) -> CaptureSelection? {
        candidate(
            for: ownerPID,
            target: target,
            candidates: candidates
        ).map { candidate in
            .window(candidate.frame, windowID: candidate.windowID)
        }
    }

    public func selection(
        forPreferredOwnerPIDs preferredOwnerPIDs: [pid_t],
        candidates: [TopWindowCaptureCandidate]
    ) -> CaptureSelection? {
        for preferredPID in preferredOwnerPIDs {
            if let candidate = candidates.first(where: { $0.ownerPID == preferredPID }) {
                return .window(candidate.frame, windowID: candidate.windowID)
            }
        }

        return nil
    }

    private func candidate(
        for ownerPID: pid_t,
        target: CurrentSpaceCaptureTarget,
        candidates: [TopWindowCaptureCandidate]
    ) -> TopWindowCaptureCandidate? {
        switch target {
        case .currentApp:
            return candidates.first { candidate in
                candidate.ownerPID == ownerPID
            }
        case .topApp:
            return candidates.first { candidate in
                candidate.ownerPID != ownerPID
            }
        }
    }
}
