// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WorldEditor-Builder",
    platforms: [
        .iOS("27.1"),
    ],
    dependencies: [
        .package(name: "RootPackage", path: "../.."),
    ],
    targets: [
        .executableTarget(
    name: "WorldEditor-App",
    dependencies: [
        .product(name: "WorldEditor", package: "RootPackage"),
    ],
    linkerSettings: [
    .unsafeFlags([
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
    ]),
]
)
    ]
)
