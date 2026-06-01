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

        // v2 architecture scaffold — compiled alongside v1, not yet integrated.
        // Entry point lives in AppModel; wired into the executable when v2 replaces v1.
        .target(
            name: "ReLayV2",
            path: "Sources/ReLayV2"
        ),

        .testTarget(
            name: "ReLayCoreTests",
            dependencies: ["ReLayCore"],
            path: "Tests/ReLayCoreTests"
        )
    ]
)
