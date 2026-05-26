// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "cshot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cshot", targets: ["cshot"]),
        .library(name: "cshotCore", targets: ["cshotCore"])
    ],
    targets: [
        .target(
            name: "cshotCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreImage")
            ]
        ),
        .executableTarget(
            name: "cshot",
            dependencies: ["cshotCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "cshotCoreTests",
            dependencies: ["cshotCore"]
        )
    ]
)
