// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleWindowSwitcher",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(
            name: "SimpleWindowSwitcher",
            targets: ["SimpleWindowSwitcher"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "SimpleWindowSwitcher",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices")
            ]
        ),
    ]
)
