import CoreGraphics
import Foundation

public struct CoordinateConverter {
    public init() {}

    public func quartzRect(fromAppKitRect rect: CGRect, screenFrames: [CGRect]) -> CGRect {
        guard let union = screenUnion(screenFrames), !rect.isNull, !rect.isEmpty else {
            return rect
        }

        return CGRect(
            x: rect.origin.x,
            y: union.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public func appKitRect(fromQuartzRect rect: CGRect, screenFrames: [CGRect]) -> CGRect {
        guard let union = screenUnion(screenFrames), !rect.isNull, !rect.isEmpty else {
            return rect
        }

        return CGRect(
            x: rect.origin.x,
            y: union.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func screenUnion(_ frames: [CGRect]) -> CGRect? {
        frames.reduce(nil) { partial, frame in
            guard let partial else {
                return frame
            }
            return partial.union(frame)
        }
    }
}
