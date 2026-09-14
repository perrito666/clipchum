// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipChum",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipChum", targets: ["ClipChum"]),
        .library(name: "ClipChumCore", targets: ["ClipChumCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "ClipChumCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "ClipChum",
            dependencies: [
                "ClipChumCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClipChumCoreTests",
            dependencies: ["ClipChumCore"]
        ),
    ]
)
