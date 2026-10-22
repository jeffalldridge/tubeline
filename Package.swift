// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tubeline",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TubelineCore", targets: ["TubelineCore"]),
        .executable(name: "tubeline", targets: ["tubeline"]),
        .executable(name: "TubelineApp", targets: ["TubelineApp"]),
    ],
    targets: [
        .target(name: "TubelineCore"),
        .executableTarget(name: "tubeline", dependencies: ["TubelineCore"]),
        .executableTarget(name: "TubelineApp", dependencies: ["TubelineCore"]),
    ],
    swiftLanguageModes: [.v5]
)
