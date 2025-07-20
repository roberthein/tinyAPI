// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tinyAPI",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "tinyAPI",
            targets: ["tinyAPI"]
        ),
    ],
    targets: [
        .target(
            name: "tinyAPI",
            swiftSettings: [
                // Strict concurrency checking (recommended for Swift 6)
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
