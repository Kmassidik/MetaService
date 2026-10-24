import XCTest
@testable import RootCore

final class TeamLimitsTests: XCTestCase {
    private let shape = SandboxShape()
    private let limits = TeamLimits(maxRunning: 2, maxVcpu: 4, maxRamMb: 1_024, maxSandboxesPerHour: 3)

    private func usage(running: Int = 0, vcpu: Int = 0, ramMb: Int = 0, createdLastHour: Int = 0) -> TeamUsage {
        TeamUsage(running: running, vcpu: vcpu, ramMb: ramMb, createdLastHour: createdLastHour)
    }

    func testTheStandardTeamIsAClosedSetOfLimits() {
        XCTAssertEqual(TeamLimits.standard.maxRunning, TeamLimits.defaultMaxRunning)
        XCTAssertEqual(TeamLimits.standard.maxVcpu, TeamLimits.defaultMaxVcpu)
        XCTAssertEqual(TeamLimits.standard.maxRamMb, TeamLimits.defaultMaxRamMb)
        XCTAssertEqual(TeamLimits.standard.maxSandboxesPerHour, TeamLimits.defaultMaxSandboxesPerHour)
    }

    func testAShapeDefaultsToTheBaseTemplate() {
        XCTAssertEqual(shape.vcpu, 2)
        XCTAssertEqual(shape.ramMb, 512)
        XCTAssertEqual(shape.diskMb, 10 * 1_024)
    }

    func testAFreshTeamCanMakeASandbox() {
        XCTAssertNil(SandboxLimits.refusal(limits, usage: usage(), shape: shape))
    }

    func testAtTheRunningLimitTheNextCreateIsRefusedWithItsOwnReason() throws {
        let refusal = try XCTUnwrap(SandboxLimits.refusal(limits, usage: usage(running: 2), shape: shape))
        XCTAssertEqual(refusal.reason, .tooManyRunning)
        XCTAssertEqual(refusal.reason.rawValue, "too_many_running")
        XCTAssertEqual(refusal.limit, 2)
        XCTAssertEqual(refusal.used, 2)
    }

    func testTheVcpuLimitIsExactAndThenRefused() throws {
        XCTAssertNil(SandboxLimits.refusal(limits, usage: usage(vcpu: 2), shape: shape))
        let refusal = try XCTUnwrap(SandboxLimits.refusal(limits, usage: usage(vcpu: 3), shape: shape))
        XCTAssertEqual(refusal.reason, .tooMuchVcpu)
        XCTAssertEqual(refusal.needed, 2)
        XCTAssertEqual(refusal.limit, 4)
    }

    func testTheMemoryLimitIsExactAndThenRefused() throws {
        XCTAssertNil(SandboxLimits.refusal(limits, usage: usage(ramMb: 512), shape: shape))
        let refusal = try XCTUnwrap(SandboxLimits.refusal(limits, usage: usage(ramMb: 513), shape: shape))
        XCTAssertEqual(refusal.reason, .tooMuchRam)
        XCTAssertEqual(refusal.reason.rawValue, "too_much_ram")
    }

    func testTheHourlyLimitRefusesTheNextCreate() throws {
        let refusal = try XCTUnwrap(SandboxLimits.refusal(limits, usage: usage(createdLastHour: 3), shape: shape))
        XCTAssertEqual(refusal.reason, .tooManyPerHour)
        XCTAssertEqual(refusal.reason.rawValue, "too_many_per_hour")
        XCTAssertNil(SandboxLimits.refusal(limits, usage: usage(createdLastHour: 2), shape: shape))
    }

    func testTheReasonsAreDistinct() {
        XCTAssertEqual(Set(TeamLimitReason.allCases.map(\.rawValue)).count, 4)
    }
}
