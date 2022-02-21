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
    targets: [
        .target(
            name: "OneState",
            dependencies: []
        )
    ]
)
