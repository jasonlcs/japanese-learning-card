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
    targets: [
        .target(
            name: "JapaneseLearningCardCore",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "JapaneseLearningCard",
            dependencies: ["JapaneseLearningCardCore"],
            exclude: [
                "Info.plist"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "JapaneseLearningCardCoreChecks",
            dependencies: ["JapaneseLearningCardCore"]
        )
    ]
)
