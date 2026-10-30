import XCTest
@testable import RootCore

final class McpQuotaTests: XCTestCase {
    private let quotas = McpQuotas.defaults
    private let none = McpUsage(aliveVms: 0, vcpu: 0, ramMb: 0, diskGb: 0, createsLastDay: 0)
    private let small = McpWish(vcpu: 1, ramMb: 2048, diskGb: 20, gpuMemoryGb: nil)

    func testTheDefaultsAreTheSpecs() {
        XCTAssertEqual(quotas.maxVms, 3)
        XCTAssertEqual(quotas.maxVcpu, 8)
        XCTAssertEqual(quotas.maxRamMb, 16_384)
        XCTAssertEqual(quotas.maxDiskGb, 200)
        XCTAssertEqual(quotas.createsPerDay, 10)
        XCTAssertEqual(quotas.gpuMemoryGb, 8)
    }

    func testAnEmptyTokenFits() {
        XCTAssertNil(McpQuotaCheck.refusal(quotas, used: none, wish: small))
    }

    func testMaxVmsRefusesTheFourthAndSaysWhatToDo() {
        let used = McpUsage(aliveVms: 3, vcpu: 3, ramMb: 6144, diskGb: 60, createsLastDay: 3)
        XCTAssertEqual(McpQuotaCheck.refusal(quotas, used: used, wish: small), "max_vms is 3 and 3 are alive: delete one first.")
        let two = McpUsage(aliveVms: 2, vcpu: 2, ramMb: 4096, diskGb: 40, createsLastDay: 2)
        XCTAssertNil(McpQuotaCheck.refusal(quotas, used: two, wish: small))
    }

    func testSingularWhenOneIsAlive() {
        let tight = McpQuotas(maxVms: 1, maxVcpu: 8, maxRamMb: 16_384, maxDiskGb: 200, createsPerDay: 10, gpuMemoryGb: 8)
        let used = McpUsage(aliveVms: 1, vcpu: 1, ramMb: 2048, diskGb: 20, createsLastDay: 1)
        XCTAssertEqual(McpQuotaCheck.refusal(tight, used: used, wish: small), "max_vms is 1 and 1 is alive: delete one first.")
    }

    func testVcpuSumNamesTheLimitTheUseAndWhatIsLeft() {
        let used = McpUsage(aliveVms: 2, vcpu: 7, ramMb: 4096, diskGb: 40, createsLastDay: 2)
        let message = McpQuotaCheck.refusal(quotas, used: used, wish: McpWish(vcpu: 2, ramMb: 2048, diskGb: 20, gpuMemoryGb: nil))
        XCTAssertEqual(message, "max_vcpu is 8 and 7 are in use: this VM needs 2 and only 1 is left. Ask for a smaller size or delete a VM first.")
        XCTAssertNil(McpQuotaCheck.refusal(quotas, used: used, wish: McpWish(vcpu: 1, ramMb: 2048, diskGb: 20, gpuMemoryGb: nil)))
    }

    func testRamSumRefusesExactlyOverTheLimit() {
        let used = McpUsage(aliveVms: 2, vcpu: 2, ramMb: 14_336, diskGb: 40, createsLastDay: 2)
        XCTAssertNil(McpQuotaCheck.refusal(quotas, used: used, wish: McpWish(vcpu: 1, ramMb: 2048, diskGb: 20, gpuMemoryGb: nil)))
        let message = McpQuotaCheck.refusal(quotas, used: used, wish: McpWish(vcpu: 1, ramMb: 2049, diskGb: 20, gpuMemoryGb: nil))
        XCTAssertEqual(message?.hasPrefix("max_ram_mb is 16384 and 14336 are in use: this VM needs 2049 and only 2048 is left."), true)
    }

    func testDiskSumRefuses() {
        let used = McpUsage(aliveVms: 2, vcpu: 2, ramMb: 4096, diskGb: 180, createsLastDay: 2)
        let message = McpQuotaCheck.refusal(quotas, used: used, wish: McpWish(vcpu: 1, ramMb: 2048, diskGb: 21, gpuMemoryGb: nil))
        XCTAssertEqual(message?.hasPrefix("max_disk_gb is 200 and 180 are in use: this VM needs 21 and only 20 is left."), true)
    }

    func testCreatesPerDayRefusesTheEleventh() {
        let used = McpUsage(aliveVms: 0, vcpu: 0, ramMb: 0, diskGb: 0, createsLastDay: 10)
        XCTAssertEqual(McpQuotaCheck.refusal(quotas, used: used, wish: small), "creates_per_day is 10 and 10 were made in the last 24 hours: try again later.")
        XCTAssertNil(McpQuotaCheck.refusal(quotas, used: McpUsage(aliveVms: 0, vcpu: 0, ramMb: 0, diskGb: 0, createsLastDay: 9), wish: small))
    }

    func testGpuMemoryCapRefusesAboveAndAllowsAtTheCap() {
        XCTAssertNil(McpQuotaCheck.refusal(quotas, used: none, wish: McpWish(vcpu: 1, ramMb: 2048, diskGb: 20, gpuMemoryGb: 8)))
        let message = McpQuotaCheck.refusal(quotas, used: none, wish: McpWish(vcpu: 1, ramMb: 2048, diskGb: 20, gpuMemoryGb: 9))
        XCTAssertEqual(message, "gpu_memory_gb is capped at 8 for this token and 9 was asked for: ask for 8 or less.")
    }

    func testTheFirstBrokenLimitIsTheOneReported() {
        let used = McpUsage(aliveVms: 3, vcpu: 8, ramMb: 16_384, diskGb: 200, createsLastDay: 10)
        XCTAssertTrue(McpQuotaCheck.refusal(quotas, used: used, wish: small)?.hasPrefix("max_vms") == true)
    }

    func testQuotasFromABodyKeepDefaultsForWhatIsLeftOut() throws {
        let body = Data(#"{"max_vms": 5, "gpu_memory_gb": 16}"#.utf8)
        let parsed = try McpQuotas(object: try StrictObject(data: body, allowed: McpQuotas.keys))
        XCTAssertEqual(parsed.maxVms, 5)
        XCTAssertEqual(parsed.gpuMemoryGb, 16)
        XCTAssertEqual(parsed.maxVcpu, 8)
    }

    func testQuotasRefuseUnknownFieldsAndNumbersOutOfRange() {
        for text in [#"{"max_vms": 0}"#, #"{"max_vms": 101}"#, #"{"max_vms": "3"}"#, #"{"max_vms": 2.5}"#, #"{"max_pcs": 1}"#, #"{"max_ram_mb": 1}"#, #"{"creates_per_day": 5000}"#] {
            XCTAssertThrowsError(try McpQuotas(object: try StrictObject(data: Data(text.utf8), allowed: McpQuotas.keys)), text)
        }
    }

    func testStoredJsonRoundTripsAndADamagedRowFallsBackToDefaults() throws {
        let custom = McpQuotas(maxVms: 7, maxVcpu: 9, maxRamMb: 1024, maxDiskGb: 5, createsPerDay: 2, gpuMemoryGb: 3)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: custom.json), as: UTF8.self)
        XCTAssertEqual(McpQuotas(stored: text), custom)
        XCTAssertEqual(McpQuotas(stored: "not json"), McpQuotas.defaults)
        XCTAssertEqual(McpQuotas(stored: #"{"max_vms": "x"}"#), McpQuotas.defaults)
    }
}
