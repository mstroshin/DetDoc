import ProjectDescription

let project = Project(
    name: "DetDocApp",
    packages: [
        // Local SwiftPM package, integrated via Xcode's native package handling
        // (resolved by the Swift toolchain, not Tuist's manifest parser).
        .local(path: "../DetDocCore"),
    ],
    targets: [
        .target(
            name: "DetDocApp",
            destinations: .macOS,
            product: .app,
            bundleId: "com.detdoc.app",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .extendingDefault(with: [
                "LSApplicationCategoryType": "public.app-category.developer-tools",
                "NSHumanReadableCopyright": "",
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "DetDocCore"),
                .package(product: "DetDocViewModels"),
            ],
            settings: .settings(base: [
                "PRODUCT_NAME": "DetDoc",
                "MARKETING_VERSION": "0.1",
                "CURRENT_PROJECT_VERSION": "1",
                "CODE_SIGNING_ALLOWED": "NO",
                "SWIFT_VERSION": "6.0",
            ])
        ),
    ]
)
