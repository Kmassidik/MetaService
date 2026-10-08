// swift-tools-version: 6.0
import PackageDescription

// Rules both the Root and the Agents use: ids, tokens, strict JSON reading, time, throttling.
let package = Package(
    name: "metaservice-shared",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MSCore", targets: ["MSCore"])],
    targets: [
        .target(name: "MSCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "MSCoreTests", dependencies: ["MSCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
