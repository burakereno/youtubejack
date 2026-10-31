// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "YouTubeJack",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "YouTubeJack", targets: ["YouTubeJack"])
    ],
    targets: [
        .target(
            name: "YouTubeJackCore",
            path: "Sources/YouTubeJackCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "YouTubeJack",
            dependencies: ["YouTubeJackCore"],
            path: "Sources/YouTubeJack",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "YouTubeJackCoreTests",
            dependencies: ["YouTubeJackCore"],
            path: "Tests/YouTubeJackCoreTests"
        ),
        .testTarget(
            name: "YouTubeJackTests",
            dependencies: ["YouTubeJack"],
            path: "Tests/YouTubeJackTests"
        )
    ]
)
