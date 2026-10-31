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
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(
            name: "Light",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Light",
            exclude: ["Info.plist", "Light.icon"]
        ),
        .executableTarget(
            name: "LightCtl",
            path: "Sources/LightCtl"
        )
    ]
)
