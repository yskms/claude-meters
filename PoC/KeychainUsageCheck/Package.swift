// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeychainUsageCheck",
    targets: [
        .executableTarget(name: "KeychainUsageCheck", path: "Sources/KeychainUsageCheck")
    ]
)
