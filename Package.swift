// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeDock",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeDockCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudeDockCoreTests",
            dependencies: ["ClaudeDockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
