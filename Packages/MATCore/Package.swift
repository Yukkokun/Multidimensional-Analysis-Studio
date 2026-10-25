// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MATCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MATCore", targets: ["MATCore"]),
        .executable(name: "matctl", targets: ["matctl"]),
    ],
    targets: [
        .target(name: "MATCore", resources: [.copy("Resources")]),
        .executableTarget(name: "matctl", dependencies: ["MATCore"]),
        .testTarget(name: "MATCoreTests", dependencies: ["MATCore"]),
    ]
)
