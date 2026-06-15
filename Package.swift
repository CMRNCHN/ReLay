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
        ),
        .executable(
            name: "ReLayMVP",
            targets: ["ReLayMVP"]
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
            path: "Sources/ReLayCore",
            plugins: []
        ),

        .target(
            name: "ReLayV2",
            path: "Sources/ReLayV2"
        ),

        .executableTarget(
            name: "ReLayMVP",
            dependencies: ["ReLayV2"],
            path: "Sources/ReLayMVP"
        ),

        .testTarget(
            name: "ReLayCoreTests",
            dependencies: ["ReLayCore"],
            path: "Tests/ReLayCoreTests"
        )
    ]
)
