// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetoucheKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RetoucheKit", targets: ["RetoucheKit"]),
    ],
    targets: [
        .target(name: "RetoucheKit"),
        .executableTarget(name: "retouche-eval", dependencies: ["RetoucheKit"]),
        .testTarget(name: "RetoucheKitTests", dependencies: ["RetoucheKit"]),
    ]
)
