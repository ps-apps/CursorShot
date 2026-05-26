import Foundation

public struct InjectionPayloadFactory {
    private let shellPathFormatter: ShellPathFormatter

    public init(
        shellPathFormatter: ShellPathFormatter = ShellPathFormatter()
    ) {
        self.shellPathFormatter = shellPathFormatter
    }

    public func payload(
        for artifact: CaptureArtifact,
        targetProfile: TargetProfile,
        mode: InjectionMode
    ) -> InjectionPayload {
        let path = artifact.imageURL.path

        switch mode {
        case .alwaysPath:
            return .text(path)
        case .alwaysImage:
            return .image(artifact.imageURL, fallbackText: plainText(path: path))
        case .smart:
            return smartPayload(path: path, imageURL: artifact.imageURL, targetProfile: targetProfile)
        }
    }

    private func smartPayload(
        path: String,
        imageURL: URL,
        targetProfile: TargetProfile
    ) -> InjectionPayload {
        switch targetProfile {
        case .terminal:
            return .text(shellPathFormatter.format(path))
        case .markdownText, .plainText, .richPaste, .unknown:
            return .image(imageURL, fallbackText: plainText(path: path))
        }
    }

    private func plainText(path: String) -> String {
        "Screenshot: \(path)"
    }
}
