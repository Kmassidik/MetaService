import XCTest
@testable import RootCore

final class McpScopeRulesTests: XCTestCase {
    func testAMissingScopeSaysWhichOne() {
        XCTAssertNil(McpScopeRules.missingScope(.read, has: [.read]))
        XCTAssertTrue(McpScopeRules.missingScope(.destroy, has: [.read, .create])?.contains("\"destroy\"") == true)
    }

    func testGpuNeedsTheGpuScopeAndSharedNeedsTheSharedScope() {
        XCTAssertNotNil(McpScopeRules.missingCreateScope(gpuMemoryGb: 4, onSharedMachine: false, has: [.read, .create]))
        XCTAssertNil(McpScopeRules.missingCreateScope(gpuMemoryGb: 4, onSharedMachine: false, has: [.create, .gpu]))
        XCTAssertNotNil(McpScopeRules.missingCreateScope(gpuMemoryGb: nil, onSharedMachine: true, has: [.create]))
        XCTAssertNil(McpScopeRules.missingCreateScope(gpuMemoryGb: nil, onSharedMachine: true, has: [.create, .shared]))
        XCTAssertNil(McpScopeRules.missingCreateScope(gpuMemoryGb: nil, onSharedMachine: false, has: [.create]))
    }
}

final class McpSizeTests: XCTestCase {
    func testThePresetsAreThePanelsPresets() {
        XCTAssertEqual(McpSize.small.preset, .init(vcpu: 1, ramMb: 2048, diskGb: 20))
        XCTAssertEqual(McpSize.medium.preset, .init(vcpu: 2, ramMb: 4096, diskGb: 40))
        XCTAssertEqual(McpSize.large.preset, .init(vcpu: 4, ramMb: 8192, diskGb: 60))
        XCTAssertNil(McpSize.custom.preset)
        XCTAssertEqual(McpSize.presets.map(\.size), [.small, .medium, .large])
    }
}

final class McpSharedTests: XCTestCase {
    func testOnlyTheJoinShareNetworkIsShared() {
        XCTAssertTrue(McpShared.isShared(ip: "10.77.0.2"))
        XCTAssertFalse(McpShared.isShared(ip: "10.77.1.2"))
        XCTAssertFalse(McpShared.isShared(ip: "192.168.1.5"))
        XCTAssertFalse(McpShared.isShared(ip: nil))
        XCTAssertFalse(McpShared.isShared(ip: "10.770.0.2"))
    }
}
