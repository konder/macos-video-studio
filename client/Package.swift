// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReelForge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ReelForge", path: "Sources/ReelForge")
    ]
)
