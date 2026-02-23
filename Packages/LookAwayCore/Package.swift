// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LookAwayCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "LookAwayCore", targets: ["LookAwayCore"]),
    ],
    targets: [
        .target(
            name: "LookAwayCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "LookAwayCoreTests",
            dependencies: ["LookAwayCore"]
        ),
    ]
)
