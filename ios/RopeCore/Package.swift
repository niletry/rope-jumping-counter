// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RopeCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "RopeCore", targets: ["RopeCore"]),
    ],
    targets: [
        .target(name: "RopeCore"),
        .testTarget(name: "RopeCoreTests", dependencies: ["RopeCore"]),
    ]
)
