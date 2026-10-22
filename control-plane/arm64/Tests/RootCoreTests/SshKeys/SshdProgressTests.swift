import XCTest
@testable import RootCore

final class SshdProgressTests: XCTestCase {
    private let start = 1_800_000_000
    private var installing: SshdProgress { SshdProgress(phase: .installing, message: nil, since: start) }

    func testAnInstallingPhaseStaysInstallingBeforeTheLimit() {
        XCTAssertEqual(installing.atTime(start + SshdProgress.installingTimeoutSeconds - 1), installing)
    }

    func testAnInstallingPhaseOlderThanTheLimitIsAFailureWithAPlainMessage() {
        let read = installing.atTime(start + SshdProgress.installingTimeoutSeconds)
        XCTAssertEqual(read.phase, .failed)
        XCTAssertEqual(read.message, SshdProgress.interruptedMessage)
        XCTAssertEqual(read.since, start + SshdProgress.installingTimeoutSeconds)
    }

    func testIdleAndFailedPhasesDoNotChangeWithTime() {
        let failed = SshdProgress(phase: .failed, message: "x", since: start)
        XCTAssertEqual(failed.atTime(start + 10_000), failed)
        XCTAssertEqual(SshdProgress.idle.atTime(start + 10_000), .idle)
    }

    func testTheHeartbeatLeavesARunningApplyAlone() {
        XCTAssertFalse(installing.mayStartFromHeartbeat(at: start + 1))
        XCTAssertFalse(installing.mayStartFromHeartbeat(at: start + SshdProgress.installingTimeoutSeconds - 1))
    }

    func testTheHeartbeatTakesIdleAtOnceAndAFailureOnlyAfterTheWait() {
        XCTAssertTrue(SshdProgress.idle.mayStartFromHeartbeat(at: start))
        let failed = SshdProgress(phase: .failed, message: "x", since: start)
        XCTAssertFalse(failed.mayStartFromHeartbeat(at: start + SshdProgress.retryWaitSeconds - 1))
        XCTAssertTrue(failed.mayStartFromHeartbeat(at: start + SshdProgress.retryWaitSeconds))
    }

    func testAnApplyThatDiedIsTriedAgainOnlyAfterTheLimitPlusTheWait() {
        XCTAssertFalse(installing.mayStartFromHeartbeat(at: start + SshdProgress.installingTimeoutSeconds + SshdProgress.retryWaitSeconds - 1))
        XCTAssertTrue(installing.mayStartFromHeartbeat(at: start + SshdProgress.installingTimeoutSeconds + SshdProgress.retryWaitSeconds))
    }

    func testTheHelpersWordsAreOnePlainLineAndNeverEmpty() {
        XCTAssertEqual(SshdProgress.failureMessage(from: "The VM could not download the SSH server."), "The VM could not download the SSH server.")
        XCTAssertEqual(SshdProgress.failureMessage(from: "line one\nline two\u{7}"), "line oneline two")
        XCTAssertEqual(SshdProgress.failureMessage(from: nil), SshdProgress.unclearFailureMessage)
        XCTAssertEqual(SshdProgress.failureMessage(from: " \n "), SshdProgress.unclearFailureMessage)
        XCTAssertEqual(SshdProgress.failureMessage(from: String(repeating: "a", count: 1000)).count, SshdProgress.maxMessageCharacters)
    }
}
