// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WindowsTaskbar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WindowsTaskbar", targets: ["WindowsTaskbar"])
    ],
    targets: [
        .executableTarget(
            name: "WindowsTaskbar",
            path: "Sources/WindowsTaskbar"
        ),
        .testTarget(
            name: "WindowsTaskbarTests",
            dependencies: ["WindowsTaskbar"],
            path: "Tests/WindowsTaskbarTests"
        )
    ]
)
