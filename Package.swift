// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WeGestureARM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WeGestureARM", targets: ["WeGestureARM"])
    ],
    targets: [
        .executableTarget(
            name: "WeGestureARM",
            path: "Sources/WeGestureARM"
        )
    ]
)
