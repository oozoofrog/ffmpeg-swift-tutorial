// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModernizationSupport",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ModernizationSupport", targets: ["ModernizationSupport"])
    ],
    targets: [
        .target(name: "ModernizationSupport"),
        .testTarget(name: "ModernizationSupportTests", dependencies: ["ModernizationSupport"])
    ]
)
