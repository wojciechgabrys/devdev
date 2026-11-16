// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DevDevCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DevDevCore", targets: ["DevDevCore"])
    ],
    targets: [
        .target(name: "DevDevCore"),
        .testTarget(name: "DevDevCoreTests", dependencies: ["DevDevCore"]),
    ]
)
