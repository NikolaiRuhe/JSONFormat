// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JSONFormat",
    platforms: [.macOS(.v12)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "JSONFormat",
            targets: ["JSONFormat"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.0.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "JSONFormat",
            dependencies: [.product(name: "AsyncAlgorithms", package: "swift-async-algorithms")]),
        .testTarget(
            name: "JSONFormatTests",
            dependencies: ["JSONFormat"],
            resources: [.process("Resources")]
        ),
    ]
)
