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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
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
            dependencies: [
                "CursorShotCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "CursorShotCoreTests",
            dependencies: ["CursorShotCore"]
        )
    ]
)
