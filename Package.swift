// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Light",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Light", targets: ["Light"]),
        .executable(name: "lightctl", targets: ["LightCtl"])
    ],
    targets: [
        .executableTarget(
            name: "Light",
            path: "Sources/Light"
        ),
        .executableTarget(
            name: "LightCtl",
            path: "Sources/LightCtl"
        )
    ]
)
