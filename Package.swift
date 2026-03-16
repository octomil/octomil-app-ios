// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OctomilApp",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/octomil/octomil-ios.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4"),
    ],
    targets: [
        .target(
            name: "OctomilAppLib",
            dependencies: [
                .product(name: "Octomil", package: "octomil-ios"),
            ],
            path: "OctomilApp",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "App/OctomilAppApp.swift",
                "Screens/ChatScreen.swift",
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
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/OctomilAppTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
