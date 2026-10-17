// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OctomilApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/octomil/octomil-ios.git", revision: "8d52d46fcd862b332f3b0ad7fe08437eff7d23a0"),
    ],
    targets: [
        .target(
            name: "OctomilAppLib",
            dependencies: [
                .product(name: "OctomilClient", package: "octomil-ios"),
            ],
            path: "OctomilApp",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "App/OctomilAppApp.swift",
                "Screens/ChatScreen.swift",
                "Screens/DetectionScreen.swift",
                "Screens/HomeScreen.swift",
                "Screens/ModelDetailScreen.swift",
                "Screens/PairScreen.swift",
                "Screens/PredictionScreen.swift",
                "Screens/SettingsScreen.swift",
                "Screens/TranscriptionScreen.swift",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "OctomilAppTests",
            dependencies: [
                "OctomilAppLib",
            ],
            path: "Tests/OctomilAppTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
