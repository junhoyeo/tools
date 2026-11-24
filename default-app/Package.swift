// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "default-app",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "default-app", targets: ["DefaultApp"]),
    ],
    targets: [
        .executableTarget(name: "DefaultApp"),
        .testTarget(name: "DefaultAppTests", dependencies: ["DefaultApp"]),
    ]
)
