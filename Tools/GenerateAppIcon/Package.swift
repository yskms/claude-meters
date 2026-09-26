// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GenerateAppIcon",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "GenerateAppIcon", path: "Sources/GenerateAppIcon")
    ]
)
