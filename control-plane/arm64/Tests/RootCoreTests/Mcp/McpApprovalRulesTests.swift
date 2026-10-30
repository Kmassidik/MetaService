import XCTest
@testable import RootCore

final class McpApprovalRulesTests: XCTestCase {
    private func shape(_ size: McpSize, _ custom: McpSize.Dimensions? = nil, gpu: Int? = nil, shared: Bool = false) -> McpApprovalRules.CreateShape {
        McpApprovalRules.CreateShape(size: size, dimensions: custom ?? size.preset!, gpuMemoryGb: gpu, onSharedMachine: shared)
    }

    func testThePresetsSmallAndMediumRunAtOnce() {
        XCTAssertNil(McpApprovalRules.reason(forCreate: shape(.small), autoApprove: false))
        XCTAssertNil(McpApprovalRules.reason(forCreate: shape(.medium), autoApprove: false))
    }

    func testLargeAlwaysNeedsAPerson() {
        XCTAssertNotNil(McpApprovalRules.reason(forCreate: shape(.large), autoApprove: false))
    }

    func testACustomSizeNeedsApprovalOnlyAboveTheMediumPreset() {
        let medium = McpSize.medium.preset!
        XCTAssertNil(McpApprovalRules.reason(forCreate: shape(.custom, medium), autoApprove: false))
        XCTAssertNil(McpApprovalRules.reason(forCreate: shape(.custom, .init(vcpu: 1, ramMb: 512, diskGb: 1)), autoApprove: false))
        XCTAssertNotNil(McpApprovalRules.reason(forCreate: shape(.custom, .init(vcpu: 3, ramMb: 4096, diskGb: 40)), autoApprove: false))
        XCTAssertNotNil(McpApprovalRules.reason(forCreate: shape(.custom, .init(vcpu: 2, ramMb: 4097, diskGb: 40)), autoApprove: false))
        XCTAssertNotNil(McpApprovalRules.reason(forCreate: shape(.custom, .init(vcpu: 2, ramMb: 4096, diskGb: 41)), autoApprove: false))
    }

    func testAGpuLimitAndASharedMachineNeedAPerson() {
        XCTAssertNotNil(McpApprovalRules.reason(forCreate: shape(.small, gpu: 4), autoApprove: false))
        XCTAssertNotNil(McpApprovalRules.reason(forCreate: shape(.small, shared: true), autoApprove: false))
    }

    func testAutoApproveSkipsEveryRuleForCreateAndDelete() {
        XCTAssertNil(McpApprovalRules.reason(forCreate: shape(.large, gpu: 8, shared: true), autoApprove: true))
        XCTAssertNil(McpApprovalRules.reason(forDelete: true))
    }

    func testADeleteAlwaysNeedsAPersonWithoutAutoApprove() {
        XCTAssertNotNil(McpApprovalRules.reason(forDelete: false))
    }

    func testAMissingScopeSaysWhichOne() {
        XCTAssertNil(McpApprovalRules.missingScope(.read, has: [.read]))
        XCTAssertTrue(McpApprovalRules.missingScope(.destroy, has: [.read, .create])?.contains("\"destroy\"") == true)
    }

    func testGpuNeedsTheGpuScopeAndSharedNeedsTheSharedScope() {
        XCTAssertNotNil(McpApprovalRules.missingCreateScope(gpuMemoryGb: 4, onSharedMachine: false, has: [.read, .create]))
        XCTAssertNil(McpApprovalRules.missingCreateScope(gpuMemoryGb: 4, onSharedMachine: false, has: [.create, .gpu]))
        XCTAssertNotNil(McpApprovalRules.missingCreateScope(gpuMemoryGb: nil, onSharedMachine: true, has: [.create]))
        XCTAssertNil(McpApprovalRules.missingCreateScope(gpuMemoryGb: nil, onSharedMachine: true, has: [.create, .shared]))
        XCTAssertNil(McpApprovalRules.missingCreateScope(gpuMemoryGb: nil, onSharedMachine: false, has: [.create]))
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

    func testExceedsMediumLooksAtEveryNumber() {
        XCTAssertFalse(McpSize.exceedsMedium(.init(vcpu: 2, ramMb: 4096, diskGb: 40)))
        XCTAssertTrue(McpSize.exceedsMedium(.init(vcpu: 3, ramMb: 1, diskGb: 1)))
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

final class McpDescribeTests: XCTestCase {
    func testACreateNamesTheExactSizeAndPlace() {
        let text = McpDescribe.action(kind: "create", params: ["name": "web", "size": "large", "vcpu": 4, "ram_mb": 8192, "disk_gb": 60, "gpu_memory_gb": 4])
        XCTAssertEqual(text, "Create a VM named \"web\" (size large: 4 CPU, 8192 MB RAM, 60 GB disk) on the least loaded machine that fits, with a GPU memory limit of 4 GB")
        let placed = McpDescribe.action(kind: "create", params: ["machine": "mini", "size": "small", "vcpu": 1, "ram_mb": 2048, "disk_gb": 20])
        XCTAssertTrue(placed.contains("on machine mini"))
    }

    func testOtherActionsNameTheVm() {
        XCTAssertEqual(McpDescribe.action(kind: "delete", params: ["machine": "mini", "vm": "wl-1", "vm_name": "web"]), "Delete the VM wl-1 (\"web\") on machine mini for good")
        XCTAssertEqual(McpDescribe.action(kind: "stop", params: ["machine": "mini", "vm": "wl-1"]), "Stop the VM wl-1 on machine mini")
    }

    func testDeniedAndExpiredHaveWords() {
        XCTAssertNotNil(McpDescribe.ending("denied"))
        XCTAssertNotNil(McpDescribe.ending("expired"))
        XCTAssertNil(McpDescribe.ending("done"))
    }
}
