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
        // The companion's model, Gemma 4 26B-A4B, runs on TurboFieldfare (Swift and
        // Metal, Apache-2.0), which keeps the model in the phone's storage and reads
        // only the experts each token needs. scripts/fetch-turbo-fieldfare.sh puts it
        // here at a pinned commit, with its installer (it downloads and repacks the
        // model on the phone) made a library: upstream builds that only into its own
        // tools. Its server's swift-nio and Mac app's SwiftMath are fetched, not built.
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
                .product(name: "TurboFieldfare", package: "turbo-fieldfare"),
                .product(name: "TurboFieldfareRepackCore", package: "turbo-fieldfare"),
            ],
            path: "App/Sources",
            // Each file sees only the modules it imports (SE-0444).
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("MemberImportVisibility")]
        ),
    ]
)
