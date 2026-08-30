// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedFoundation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SharedFoundation", targets: ["SharedFoundation"]),
    ],
    targets: [
        .target(name: "SharedFoundation"),
    ]
)
