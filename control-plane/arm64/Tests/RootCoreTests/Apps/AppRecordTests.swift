import XCTest
@testable import RootCore

final class AppRecordTests: XCTestCase {
    private let start = 1_800_000_000

    private func record(_ phase: AppPhase, startedAt: Int? = nil, updatedAt: Int? = nil) -> AppRecord {
        AppRecord(app: "openclaw", phase: phase, message: phase == .failed ? "no" : nil, version: nil, installerSha256: nil, logTail: [], startedAt: startedAt, updatedAt: updatedAt ?? start)
    }

    func testAnInstallThatBeganLongAgoReadsAsFailedWithAPlainMessage() {
        let installing = record(.installing, startedAt: start)
        XCTAssertEqual(installing.atTime(start + AppRecord.installingTimeoutSeconds - 1).phase, .installing)
        let late = installing.atTime(start + AppRecord.installingTimeoutSeconds)
        XCTAssertEqual(late.phase, .failed)
        XCTAssertEqual(late.message, "Setting up the app did not finish. The parent may have restarted. Try again.")
        XCTAssertEqual(late.updatedAt, start + AppRecord.installingTimeoutSeconds)
    }

    func testTheTimeoutIsThirtyMinutesAndTheRetryWaitIsOneMinute() {
        XCTAssertEqual(AppRecord.installingTimeoutSeconds, 1800)
        XCTAssertEqual(AppRecord.retryWaitSeconds, 60)
    }

    func testOtherPhasesDoNotChangeWithTime() {
        for phase in [AppPhase.none, .ready, .failed] { XCTAssertEqual(record(phase).atTime(start + 999_999), record(phase)) }
    }

    func testTheHeartbeatStartsAWantedInstallAtOnceButNotARunningOrFinishedOne() {
        XCTAssertTrue(record(.none).mayStartFromHeartbeat(at: start))
        XCTAssertFalse(record(.installing, startedAt: start).mayStartFromHeartbeat(at: start + 10))
        XCTAssertFalse(record(.ready).mayStartFromHeartbeat(at: start + 10_000))
    }

    func testAFailedInstallWaitsItsMinuteBeforeTheHeartbeatTriesAgain() {
        let failed = record(.failed, updatedAt: start)
        XCTAssertFalse(failed.mayStartFromHeartbeat(at: start + AppRecord.retryWaitSeconds - 1))
        XCTAssertTrue(failed.mayStartFromHeartbeat(at: start + AppRecord.retryWaitSeconds))
    }

    func testAnInstallThatTimedOutMayBeRetriedAfterTheWaitFollowingTheTimeout() {
        let installing = record(.installing, startedAt: start)
        let timedOut = start + AppRecord.installingTimeoutSeconds
        XCTAssertFalse(installing.mayStartFromHeartbeat(at: timedOut + AppRecord.retryWaitSeconds - 1))
        XCTAssertTrue(installing.mayStartFromHeartbeat(at: timedOut + AppRecord.retryWaitSeconds))
    }
}
