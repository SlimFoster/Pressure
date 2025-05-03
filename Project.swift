import ProjectDescription

let project = Project(
    name: "Pressure",
    organizationName: "com.pressure",
    options: .options(
        automaticSchemesOptions: .disabled
    ),
    packages: [
        .remote(url: "https://github.com/tsolomko/SWCompression.git", requirement: .upToNextMajor(from: "4.8.0")),
        .remote(url: "https://github.com/weichsel/ZIPFoundation.git", requirement: .upToNextMajor(from: "0.9.0")),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.9",
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "Pressure",
            destinations: [.mac],
            product: .app,
            bundleId: "com.pressure.Pressure",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleName": "Pressure",
                    "CFBundleDisplayName": "Pressure",
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1",
                    "LSMinimumSystemVersion": "13.0",
                    "NSHumanReadableCopyright": "Copyright © 2024. All rights reserved.",
                    "NSPrincipalClass": "NSApplication",
                    "NSHighResolutionCapable": true,
                ]
            ),
            sources: [
                .glob("Sources/Pressure/**/*.swift"),
            ],
            resources: [
                .glob(pattern: "Resources/**", excluding: ["Resources/Info.plist"]),
            ],
            dependencies: [
                .package(product: "SWCompression", type: .runtime),
                .package(product: "ZIPFoundation", type: .runtime),
            ],
            settings: .settings(
                base: [
                    "INFOPLIST_FILE": "Resources/Info.plist",
                    "DEVELOPMENT_TEAM": "",
                    "CODE_SIGN_IDENTITY": "-",
                    "CODE_SIGNING_REQUIRED": "YES",
                    "CODE_SIGNING_ALLOWED": "YES",
                    "AD_HOC_CODE_SIGNING_ALLOWED": "YES",
                ]
            )
        ),
        .target(
            name: "PressureTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.pressure.PressureTests",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .default,
            sources: [
                .glob("Tests/PressureTests/**/*.swift"),
            ],
            dependencies: [
                .target(name: "Pressure"),
                .package(product: "SWCompression", type: .runtime),
                .package(product: "ZIPFoundation", type: .runtime),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_IDENTITY": "",
                    "CODE_SIGNING_REQUIRED": "NO",
                ]
            )
        ),
        .target(
            name: "PressureUITests",
            destinations: [.mac],
            product: .uiTests,
            bundleId: "com.pressure.PressureUITests",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .default,
            sources: [
                .glob("Tests/PressureUITests/**/*.swift"),
            ],
            dependencies: [
                .target(name: "Pressure"),
                .package(product: "SWCompression", type: .runtime),
                .package(product: "ZIPFoundation", type: .runtime),
            ],
            settings: .settings(
                base: [
                    "TEST_TARGET_NAME": "Pressure",
                    "CODE_SIGN_IDENTITY": "-",
                    "CODE_SIGNING_REQUIRED": "YES",
                    "CODE_SIGNING_ALLOWED": "YES",
                    "DEVELOPMENT_TEAM": "",
                    "AD_HOC_CODE_SIGNING_ALLOWED": "YES",
                ]
            )
        ),
    ],
    schemes: [
        // App scheme - build and run the app only
        .scheme(
            name: "Pressure",
            shared: true,
            buildAction: .buildAction(targets: ["Pressure"]),
            runAction: .runAction(executable: "Pressure")
        ),
        // Unit tests scheme - build and run unit tests only
        .scheme(
            name: "PressureTests",
            shared: true,
            buildAction: .buildAction(targets: ["Pressure", "PressureTests"]),
            testAction: .targets(
                ["PressureTests"],
                configuration: .debug,
                options: .options(
                    coverage: false
                )
            )
        ),
        // UI tests scheme - build and run UI tests only
        .scheme(
            name: "PressureUITests",
            shared: true,
            buildAction: .buildAction(targets: ["Pressure", "PressureUITests"]),
            testAction: .targets(
                ["PressureUITests"],
                configuration: .debug,
                options: .options(
                    coverage: false
                )
            )
        ),
    ]
)
