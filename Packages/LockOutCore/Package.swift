// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LockOutCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LockOutCore", targets: ["LockOutCore"]),
    ],
    targets: [
        .target(
            name: "LockOutCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "LockOutCoreTests",
            dependencies: ["LockOutCore"]
        ),
    ]
)
