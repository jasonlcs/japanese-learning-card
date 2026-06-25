// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JapaneseLearningCard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "JapaneseLearningCard", targets: ["JapaneseLearningCard"]),
        .executable(name: "JapaneseLearningCardCoreChecks", targets: ["JapaneseLearningCardCoreChecks"]),
        .library(name: "JapaneseLearningCardCore", targets: ["JapaneseLearningCardCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "JapaneseLearningCardCore",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("CloudKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "JapaneseLearningCard",
            dependencies: [
                "JapaneseLearningCardCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: [
                "Info.plist",
                "JapaneseLearningCard.entitlements",
                "JapaneseLearningCard.entitlements.ad-hoc",
                "Resources/AppIcon.icns"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "JapaneseLearningCardCoreChecks",
            dependencies: ["JapaneseLearningCardCore"]
        )
    ]
)
