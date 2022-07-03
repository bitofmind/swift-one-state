// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "swift-one-state",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(name: "OneState", targets: ["OneState"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", "0.0.0"..<"0.0.2"),
    ],
    targets: [
        .target(
            name: "OneState",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]
        )
    ]
)
