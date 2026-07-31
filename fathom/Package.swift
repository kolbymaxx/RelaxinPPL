// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fathom",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "FathomCore", targets: ["FathomCore"]),
        .library(name: "FathomEngine", targets: ["FathomEngine"]),
        .executable(name: "fathom-theory", targets: ["FathomTheoryCLI"]),
    ],
    targets: [
        .target(name: "FathomCore"),
        .target(name: "FathomEngine", dependencies: ["FathomCore"]),
        .executableTarget(name: "FathomTheoryCLI", dependencies: ["FathomEngine"]),
    ]
)
