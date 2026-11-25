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
            ],
            path: "App/Sources",
            // Each file sees only the modules it imports (SE-0444).
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("MemberImportVisibility")]
        ),
        // The companion's model runs on llama.cpp (MIT): its prebuilt Apple framework, which
        // scripts/fetch-llama.sh puts here (checked).
        .binaryTarget(name: "llama", path: "Vendor/llama.xcframework"),
    ]
)
