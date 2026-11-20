// swift-tools-version: 6.2
// WriterKit: platform-independent logic. Foundation only, so it builds and
// tests on Linux CI as well as Apple platforms. Anything that needs UIKit,
// Core ML, Foundation Models or llama.cpp lives in the app target instead.
import PackageDescription

let package = Package(
    name: "WriterKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WriterCore", targets: ["WriterCore"]),
        .library(name: "FocusLayout", targets: ["FocusLayout"]),
        .library(name: "Provenance", targets: ["Provenance"]),
        .library(name: "Guardrails", targets: ["Guardrails"]),
        .library(name: "ModelCatalog", targets: ["ModelCatalog"]),
    ],
    targets: [
        .target(name: "WriterCore"),
        .target(name: "FocusLayout"),
        .target(name: "Provenance", dependencies: ["WriterCore"]),
        .target(name: "Guardrails", dependencies: ["WriterCore", "Provenance"]),
        .target(name: "ModelCatalog"),

        .testTarget(name: "WriterCoreTests", dependencies: ["WriterCore"]),
        .testTarget(name: "FocusLayoutTests", dependencies: ["FocusLayout"]),
        .testTarget(name: "ProvenanceTests", dependencies: ["Provenance", "WriterCore"]),
        .testTarget(name: "GuardrailsTests", dependencies: ["Guardrails", "Provenance", "WriterCore"]),
        .testTarget(name: "ModelCatalogTests", dependencies: ["ModelCatalog"]),
    ],
    swiftLanguageModes: [.v6]
)
