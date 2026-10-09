// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "metaservice-root",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "metaservice-root", targets: ["Root"])],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
        .package(path: "../shared/metaservice-shared"),
    ],
    targets: [
        // Pure rules, no I/O: validation, tokens, states, throttling, cookies. Testable on their own.
        .target(name: "RootCore", dependencies: [.product(name: "MSCore", package: "metaservice-shared")], swiftSettings: [.swiftLanguageMode(.v5)]),
        // SQLite with bound parameters only, migrations, and one small store per table.
        .target(name: "RootStore", dependencies: ["RootCore"], swiftSettings: [.swiftLanguageMode(.v5)],
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "Root",
            dependencies: ["RootCore", "RootStore", .product(name: "Hummingbird", package: "hummingbird")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "RootCoreTests", dependencies: ["RootCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "RootStoreTests", dependencies: ["RootStore", "RootCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
