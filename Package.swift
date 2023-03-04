// swift-tools-version:5.7

import PackageDescription

let swiftSettings: [SwiftSetting] = []//[SwiftSetting.unsafeFlags(["-Xfrontend", "-warn-concurrency"])]

let package = Package(
    name: "swift-one-state",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .tvOS(.v14),
        .watchOS(.v7)
    ],
    products: [
        .library(name: "OneState", targets: ["OneState"]),
        .library(name: "OneStateExtensions", targets: ["OneStateExtensions"]),

    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "0.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.6.0"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "0.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "0.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.11.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "OneState",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "OneStateExtensions",
            dependencies: [
                "OneState",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "OneStateTests",
            dependencies: ["OneState"],
            swiftSettings: swiftSettings
        )
    ]
)
