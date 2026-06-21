// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DetDocCore",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "DetDocCore", targets: ["DetDocCore"]),
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
        .testTarget(
            name: "DetDocCoreTests",
            dependencies: ["DetDocCore"],
            resources: [
                .copy("Support/fake-pi.sh"),
                .copy("Support/fake-pi-plan.jsonl"),
            ]
        ),
    ]
)
