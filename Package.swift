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
        // The companion's model: llama.cpp through Hugging Face's AnyLanguageModel,
        // Foundation Models' session API on top (tools, streaming, images).
        .package(url: "https://github.com/huggingface/AnyLanguageModel", .upToNextMinor(from: "1.4.1"), traits: ["Llama"]),
        // Its Hugging Face client, to download the model with progress shown.
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "WorldEditor",
            dependencies: [
                .product(name: "WriterCore", package: "WriterKit"),
                .product(name: "FocusLayout", package: "WriterKit"),
                .product(name: "Provenance", package: "WriterKit"),
                .product(name: "Guardrails", package: "WriterKit"),
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "App/Sources",
            // Each file sees only the modules it imports: Apple's Foundation Models and
            // AnyLanguageModel name their types alike (SE-0444).
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("MemberImportVisibility")]
        ),
    ]
)
