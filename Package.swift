// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReLay",
    platforms: [
        .macOS(.v14)
    ],

    products: [
        .executable(
            name: "ReLay",
            targets: ["ReLay"]
        )
    ],

    targets: [

        .executableTarget(
            name: "ReLay",
            dependencies: ["ReLayCore"],
            path: "Sources/ReLay"
        ),

        .target(
            name: "ReLayCore",
            path: "Sources/ReLayCore"
        ),

        .testTarget(
            name: "ReLayCoreTests",
            dependencies: ["ReLayCore"],
            path: "Tests/ReLayCoreTests"
        )
    ]
)
