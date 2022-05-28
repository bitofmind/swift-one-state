// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "swift-one-state",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "OneState", targets: ["OneState"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "0.0.0"),
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
