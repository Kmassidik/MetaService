import XCTest
@testable import RootCore

final class SandboxUsageTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let shape = SandboxShape(vcpu: 2, ramMb: 512, diskMb: 10_240)

    func testUsageIsSecondsTimesVcpuAndMemory() {
        let totals = SandboxUsageMath.totals(from: start, to: start.addingTimeInterval(90), shape: shape)
        XCTAssertEqual(totals.seconds, 90)
        XCTAssertEqual(totals.vcpuSeconds, 180)
        XCTAssertEqual(totals.ramMbSeconds, 46_080)
    }

    func testARunThatDidNotAdvanceCountsNothing() {
        let backwards = SandboxUsageMath.totals(from: start, to: start.addingTimeInterval(-30), shape: shape)
        XCTAssertEqual(backwards.seconds, 0)
        XCTAssertEqual(backwards.vcpuSeconds, 0)
        XCTAssertEqual(backwards.ramMbSeconds, 0)
        XCTAssertEqual(SandboxUsageMath.seconds(from: start, to: start), 0)
    }

    func testPartOfASecondIsDroppedNotRoundedUp() {
        XCTAssertEqual(SandboxUsageMath.seconds(from: start, to: start.addingTimeInterval(90.9)), 90)
    }

    func testAnEndTimeIsTheTimeoutFromNow() throws {
        let endAt = try SandboxEndTime.end(createdAt: start, now: start, timeoutSeconds: SandboxEndTime.defaultTimeoutSeconds)
        XCTAssertEqual(endAt, start.addingTimeInterval(300))
        XCTAssertEqual(SandboxEndTime.defaultTimeoutSeconds, 300)
    }

    func testATimeoutBelowTheMinimumIsRefused() {
        XCTAssertThrowsError(try SandboxEndTime.end(createdAt: start, now: start, timeoutSeconds: 0)) {
            XCTAssertEqual(($0 as? SandboxEndTime.Refusal)?.reason, .timeoutTooShort)
        }
        XCTAssertThrowsError(try SandboxEndTime.end(createdAt: start, now: start, timeoutSeconds: -5))
    }

    func testATimeoutPastTheLongestLifeIsRefusedWithTheLongestAllowed() {
        XCTAssertThrowsError(try SandboxEndTime.end(createdAt: start, now: start, timeoutSeconds: SandboxEndTime.maximumLifeSeconds + 1)) {
            let refusal = $0 as? SandboxEndTime.Refusal
            XCTAssertEqual(refusal?.reason, .timeoutTooLong)
            XCTAssertEqual(refusal?.maximumSeconds, SandboxEndTime.maximumLifeSeconds)
        }
        XCTAssertNoThrow(try SandboxEndTime.end(createdAt: start, now: start, timeoutSeconds: SandboxEndTime.maximumLifeSeconds))
    }

    func testMovingTheTimeoutLaterStillStopsAtTheLongestLife() throws {
        let now = start.addingTimeInterval(100)
        XCTAssertEqual(SandboxEndTime.longestTimeout(createdAt: start, now: now), SandboxEndTime.maximumLifeSeconds - 100)
        XCTAssertNoThrow(try SandboxEndTime.end(createdAt: start, now: now, timeoutSeconds: SandboxEndTime.maximumLifeSeconds - 100))
        XCTAssertThrowsError(try SandboxEndTime.end(createdAt: start, now: now, timeoutSeconds: SandboxEndTime.maximumLifeSeconds - 99)) {
            XCTAssertEqual(($0 as? SandboxEndTime.Refusal)?.maximumSeconds, SandboxEndTime.maximumLifeSeconds - 100)
        }
    }

    func testTheLongestTimeoutIsNeverNegative() {
        let late = start.addingTimeInterval(Double(SandboxEndTime.maximumLifeSeconds) + 10)
        XCTAssertEqual(SandboxEndTime.longestTimeout(createdAt: start, now: late), 0)
    }

    func testTheTimeLeftIsNeverNegative() {
        XCTAssertEqual(SandboxEndTime.remainingSeconds(until: start.addingTimeInterval(45), now: start), 45)
        XCTAssertEqual(SandboxEndTime.remainingSeconds(until: start, now: start.addingTimeInterval(1)), 0)
        XCTAssertEqual(SandboxEndTime.remainingSeconds(until: start.addingTimeInterval(45.9), now: start), 45)
    }

    func testOnlyNonPausedStatesHoldComputeAndEverythingAliveHoldsDisk() {
        XCTAssertTrue(SandboxState.running.holdsCompute)
        XCTAssertTrue(SandboxState.starting.holdsCompute)
        XCTAssertTrue(SandboxState.stopping.holdsCompute)
        XCTAssertFalse(SandboxState.paused.holdsCompute)
        XCTAssertFalse(SandboxState.ended.holdsCompute)
        XCTAssertTrue(SandboxState.paused.holdsDisk)
        XCTAssertFalse(SandboxState.ended.holdsDisk)
        XCTAssertFalse(SandboxState.ended.isAlive)
    }

    func testTheEndReasonsUseTheHelpersWords() {
        XCTAssertEqual(SandboxEndReason.outOfMemory.rawValue, "out_of_memory")
        XCTAssertEqual(SandboxEndReason.helperRestart.rawValue, "helper_restart")
        XCTAssertEqual(SandboxEndReason.timeout.rawValue, "timeout")
    }
}
