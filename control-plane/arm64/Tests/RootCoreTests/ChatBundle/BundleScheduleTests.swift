import XCTest
@testable import RootCore

final class BundleScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func last(_ kind: BundleCommandKind, _ state: String, finishedAgo: TimeInterval? = nil) -> BundleCommandFacts {
        BundleCommandFacts(kind: kind, state: state, finishedAt: finishedAgo.map { now.addingTimeInterval(-$0) })
    }

    func testWithNoEarlierCommandAnInstallIsDue() {
        XCTAssertTrue(BundleSchedule.isDue(last: nil, now: now))
    }

    func testAnInstallIsNotStartedWhileOneIsGoing() {
        XCTAssertFalse(BundleSchedule.isDue(last: last(.install, "running"), now: now))
        XCTAssertFalse(BundleSchedule.isDue(last: last(.install, "queued"), now: now))
    }

    func testAFinishedInstallLeavesTheNextOneDue() {
        XCTAssertTrue(BundleSchedule.isDue(last: last(.install, "succeeded", finishedAgo: 5), now: now))
    }

    func testAFailedInstallWaitsBeforeItIsTriedAgain() {
        XCTAssertFalse(BundleSchedule.isDue(last: last(.install, "failed", finishedAgo: BundleSchedule.retryAfter - 1), now: now))
        XCTAssertTrue(BundleSchedule.isDue(last: last(.install, "failed", finishedAgo: BundleSchedule.retryAfter + 1), now: now))
        XCTAssertFalse(BundleSchedule.isDue(last: last(.install, "failed"), now: now), "a failure with no finish time is not retried")
    }

    /// Regression: the person turns Ruvio off while the machine still reports the old version for a moment. The parent must not put it back.
    func testTurningTheChatOffIsNeverUndoneByTheParent() {
        for state in ["queued", "running", "succeeded", "failed"] {
            XCTAssertFalse(BundleSchedule.isDue(last: last(.uninstall, state, finishedAgo: 100_000), now: now), state)
        }
    }
}
