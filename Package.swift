// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OctomilApp",
    platforms: [
        .iOS(.v16),
    ],
    dependencies: [
        .package(url: "https://github.com/octomil/octomil-ios.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "OctomilApp",
            dependencies: [
                .product(name: "OctomilClient", package: "octomil-ios"),
                .product(name: "OctomilUI", package: "octomil-ios"),
            ],
            path: "OctomilApp"
        ),
    ]
)
