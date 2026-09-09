// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PayOrcSDK",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "PayOrcSDK",
            targets: ["PayOrcSDK"]
        )
    ],
    targets: [
        .target(
            name: "PayOrcSDK",
            path: "Sources/PayOrcSDK",
            resources: [
                .process("Resources/PayOrcMedia.xcassets")
            ],
            swiftSettings: [
                // The SDK is UIKit UI code authored for a main-actor-by-default
                // module (the host app builds with SWIFT_DEFAULT_ACTOR_ISOLATION =
                // MainActor). Reproduce that here so isolation checking matches.
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
