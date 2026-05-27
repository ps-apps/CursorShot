// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CursorShot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CursorShot", targets: ["CursorShot"]),
        .library(name: "CursorShotCore", targets: ["CursorShotCore"])
    ],
    targets: [
        .target(
            name: "CursorShotCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreImage")
            ]
        ),
        .executableTarget(
            name: "CursorShot",
            dependencies: ["CursorShotCore"],
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
            name: "CursorShotCoreTests",
            dependencies: ["CursorShotCore"]
        )
    ]
)
