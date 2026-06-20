// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DetDocCore",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "DetDocCore", targets: ["DetDocCore"]),
        .library(name: "DetDocViewModels", targets: ["DetDocViewModels"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "DetDocCore",
            dependencies: [.product(name: "Yams", package: "Yams")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "DetDocViewModels",
            dependencies: ["DetDocCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "DetDocCoreTests",
            dependencies: ["DetDocCore"]
        ),
        .testTarget(
            name: "DetDocViewModelsTests",
            dependencies: ["DetDocViewModels", "DetDocCore"]
        ),
    ]
)
