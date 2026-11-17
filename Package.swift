// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MemBar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "MemBar", path: "Sources/MemBar"),
        .testTarget(name: "MemBarTests", dependencies: ["MemBar"]),
    ]
)
