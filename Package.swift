// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NetEaseTVCore",
    platforms: [.macOS(.v15), .tvOS(.v17)],
    products: [
        .library(name: "NetEaseTVCore", targets: ["NetEaseTVCore"]),
    ],
    targets: [
        .target(
            name: "NetEaseTVCore",
            path: "NetEaseTV/Core",
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
            name: "NetEaseTVCoreTests",
            dependencies: ["NetEaseTVCore"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
