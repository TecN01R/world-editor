// swift-tools-version: 6.2
// The iOS app as a Swift package, so xtool can build and install it from
// Linux (`xtool dev`). CI and TestFlight build the same sources through the
// XcodeGen project in project.yml.
import PackageDescription

let package = Package(
    name: "WorldEditor",
    platforms: [.iOS("27.1")],   // the Duo ships on iOS 27.1
    products: [
        .library(name: "WorldEditor", targets: ["WorldEditor"]),
    ],
    dependencies: [
        .package(path: "Packages/WriterKit"),
        // TRIAL, debug builds only (Kevin, 2026-11-25): Gemma 4 26B-A4B again, on TurboFieldfare
        // (Swift and Metal, Apache-2.0), to compare with Nemotron on the phone's higher memory
        // limit (TurboModel). scripts/fetch-turbo-fieldfare.sh puts it here at a pinned commit,
        // its installer made a library. A release build links it but never uses it; it goes
        // once the trial is over.
        .package(path: "Vendor/turbo-fieldfare"),
    ],
    targets: [
        .target(
            name: "WorldEditor",
            dependencies: [
                .product(name: "WriterCore", package: "WriterKit"),
                .product(name: "FocusLayout", package: "WriterKit"),
                .product(name: "Provenance", package: "WriterKit"),
                .product(name: "Guardrails", package: "WriterKit"),
                "llama",
                .product(name: "TurboFieldfare", package: "turbo-fieldfare"),
                .product(name: "TurboFieldfareRepackCore", package: "turbo-fieldfare"),
            ],
            path: "App/Sources",
            // Each file sees only the modules it imports (SE-0444).
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("MemberImportVisibility")]
        ),
        // The companion's model runs on llama.cpp (MIT): its prebuilt Apple framework, the
        .binaryTarget(name: "llama", path: "Vendor/llama.xcframework"),
    ]
)
