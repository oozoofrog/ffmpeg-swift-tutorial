// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModernizationSupport",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "ModernizationSupport", targets: ["ModernizationSupport"])
    ],
    targets: [
        .target(name: "ModernizationSupport"),
        .testTarget(name: "ModernizationSupportTests", dependencies: ["ModernizationSupport"])
    ]
)
