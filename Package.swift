// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SonimbusCore",
    platforms: [.macOS(.v15), .tvOS(.v17)],
    products: [
        .library(name: "SonimbusCore", targets: ["SonimbusCore"]),
    ],
    targets: [
        .target(
            name: "SonimbusCore",
            path: "Sonimbus/Core",
            exclude: ["AccountStore.swift", "PlayerService.swift", "MediaTransferService.swift"],
            sources: [
                "Models.swift",
                "NowPlayingInteraction.swift",
                "LyricsParser.swift",
                "NeteaseCrypto.swift",
                "NeteaseClient.swift",
                "NeteaseAPI.swift",
                "ContentStore.swift",
                "UnblockService.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SonimbusCoreTests",
            dependencies: ["SonimbusCore"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
