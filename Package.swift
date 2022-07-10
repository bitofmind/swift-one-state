// swift-tools-version:5.6

import PackageDescription

#if swift(>=5.7)
let asyncAlgorithms: Package.Dependency = .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "0.0.2")
let swiftSettings: [SwiftSetting] = []//[SwiftSetting.unsafeFlags(["-Xfrontend", "-warn-concurrency"])]
#else
let asyncAlgorithms: Package.Dependency = .package(url: "https://github.com/apple/swift-async-algorithms.git", "0.0.0"..<"0.0.2")
let swiftSettings: [SwiftSetting] = []
#endif

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
        asyncAlgorithms
    ],
    targets: [
        .target(
            name: "OneState",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            swiftSettings: swiftSettings
        )
    ]
)
