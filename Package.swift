// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JapaneseLearningCard",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "JapaneseLearningCard", targets: ["JapaneseLearningCard"]),
        .executable(name: "JapaneseLearningCardCoreChecks", targets: ["JapaneseLearningCardCoreChecks"]),
        .library(name: "JapaneseLearningCardCore", targets: ["JapaneseLearningCardCore"]),
        .library(name: "JapaneseLearningCardUI", targets: ["JapaneseLearningCardUI"])
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
        // Shared UI library: AppViewModel, all SwiftUI views, BrowserFallbackCrawler.
        // Available on both macOS and iOS; platform-specific code is guarded with
        // #if os(macOS) / #if os(iOS) inside each file.
        .target(
            name: "JapaneseLearningCardUI",
            dependencies: ["JapaneseLearningCardCore"],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        // macOS menu-bar app.  Depends on the shared UI library plus Sparkle.
        .executableTarget(
            name: "JapaneseLearningCard",
            dependencies: [
                "JapaneseLearningCardUI",
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
        // iOS app.  Only depends on the shared UI library.
        .executableTarget(
            name: "JapaneseLearningCardIOS",
            dependencies: ["JapaneseLearningCardUI"]
        ),
        .executableTarget(
            name: "JapaneseLearningCardCoreChecks",
            dependencies: ["JapaneseLearningCardCore"]
        )
    ]
)
