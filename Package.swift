// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SLMPluginsUpdater",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SLMPluginsUpdater",
            path: "Sources/SLMPluginsUpdater",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
