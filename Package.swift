// swift-tools-version:6.0
import PackageDescription

// The geometry engine and command-line tool. The Mac app lives in app/ and
// links TubelineCore from this package (see app/project.yml).

let package = Package(
    name: "Tubeline",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TubelineCore", targets: ["TubelineCore"]),
        .executable(name: "tubeline", targets: ["tubeline"]),
    ],
    targets: [
        .target(name: "TubelineCore"),
        .executableTarget(name: "tubeline", dependencies: ["TubelineCore"]),
    ],
    swiftLanguageModes: [.v5]
)
