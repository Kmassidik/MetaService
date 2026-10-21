// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "metaservice-agent-macos",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "metaservice-agent", targets: ["Agent"])],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", exact: "2.7.0"),
        .package(path: "../../shared/metaservice-shared"),
    ],
    targets: [
        // The pty calls (openpty, TIOCSWINSZ) that Swift cannot spell on its own.
        .target(name: "CPTY"),
        // Agent rules: request shapes, the space budget, the engine interface, the command ledger, the console rules. System calls only in Terminal/PtyProcess.
        .target(name: "AgentCore", dependencies: ["CPTY", .product(name: "MSCore", package: "metaservice-shared")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Agent",
            dependencies: ["AgentCore", .product(name: "MSCore", package: "metaservice-shared"), .product(name: "Hummingbird", package: "hummingbird"),
                          .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore", .product(name: "MSCore", package: "metaservice-shared")], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
