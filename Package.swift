// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RightKeyGesture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RightKeyGesture", targets: ["RightKeyGesture"])
    ],
    targets: [
        .executableTarget(
            name: "RightKeyGesture",
            path: "Sources/RightKeyGesture"
        )
    ]
)
