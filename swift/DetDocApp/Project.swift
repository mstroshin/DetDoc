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
            // Xcode 16 buildable folder: the Sources/ directory is referenced as a
            // file-system-synchronized group, so files added/removed under it are
            // picked up without regenerating the project.
            buildableFolders: ["Sources"],
            dependencies: [
                .package(product: "DetDocCore"),
            ],
            settings: .settings(base: [
                "PRODUCT_NAME": "DetDoc",
                "MARKETING_VERSION": "0.1",
                "CURRENT_PROJECT_VERSION": "1",
                "CODE_SIGNING_ALLOWED": "NO",
                "SWIFT_VERSION": "6.0",
            ])
        ),
        .target(
            name: "DetDocAppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.detdoc.app.tests",
            deploymentTargets: .macOS("27.0"),
            // The view-model tests live here now (moved out of the DetDocCore
            // package); the Tests/ folder is a file-system-synchronized group.
            buildableFolders: ["Tests"],
            dependencies: [
                .target(name: "DetDocApp"),
                // Needed for `@testable import DetDocCore` in the VM fixtures.
                .package(product: "DetDocCore"),
            ],
            settings: .settings(base: [
                "CODE_SIGNING_ALLOWED": "NO",
                "SWIFT_VERSION": "6.0",
                // The host app's PRODUCT_NAME is "DetDoc", so the executable is
                // DetDoc.app/Contents/MacOS/DetDoc (and its Swift module is `DetDoc`,
                // which is what the tests `@testable import`). Point TEST_HOST at that
                // executable explicitly — Tuist otherwise derives it from the target
                // name (DetDocApp) and picks the wrong leaf.
                "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/DetDoc.app/Contents/MacOS/DetDoc",
                "BUNDLE_LOADER": "$(TEST_HOST)",
            ])
        ),
    ]
)
