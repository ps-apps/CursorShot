import Foundation

public struct TargetProfileClassifier {
    private let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
        "com.github.ghostty",
        "co.zeit.hyper"
    ]

    private let markdownBundleIds: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "dev.zed.Zed",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.github.atom",
        "com.barebones.bbedit"
    ]

    private let plainTextBundleIds: Set<String> = [
        "com.apple.TextEdit",
        "com.apple.Notes"
    ]

    private let richPasteBundleIds: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.apple.MobileSMS",
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox"
    ]

    public init() {}

    public func classify(bundleId: String?, appName: String?) -> TargetProfile {
        guard let bundleId, !bundleId.isEmpty else {
            return classifyByName(appName)
        }

        if terminalBundleIds.contains(bundleId) {
            return .terminal
        }

        if markdownBundleIds.contains(bundleId) || bundleId.hasPrefix("com.jetbrains.") {
            return .markdownText
        }

        if plainTextBundleIds.contains(bundleId) {
            return .plainText
        }

        if richPasteBundleIds.contains(bundleId) {
            return .richPaste
        }

        return classifyByName(appName)
    }

    private func classifyByName(_ appName: String?) -> TargetProfile {
        let normalizedName = (appName ?? "").lowercased()

        if normalizedName.contains("terminal")
            || normalizedName.contains("iterm")
            || normalizedName.contains("warp")
            || normalizedName.contains("ghostty")
        {
            return .terminal
        }

        if normalizedName.contains("code")
            || normalizedName.contains("cursor")
            || normalizedName.contains("zed")
            || normalizedName.contains("xcode")
            || normalizedName.contains("intellij")
            || normalizedName.contains("webstorm")
            || normalizedName.contains("pycharm")
        {
            return .markdownText
        }

        if normalizedName.contains("slack")
            || normalizedName.contains("discord")
            || normalizedName.contains("messages")
            || normalizedName.contains("chrome")
            || normalizedName.contains("safari")
            || normalizedName.contains("arc")
        {
            return .richPaste
        }

        if normalizedName.contains("textedit") || normalizedName.contains("notes") {
            return .plainText
        }

        return .unknown
    }
}
