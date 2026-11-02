import XCTest
@testable import RootCore

final class JobRulesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheLimitsAreOneTableWithTheAgreedNumbers() {
        XCTAssertEqual(JobLimits.seconds(forType: "delete"), 30 * 60)
        XCTAssertEqual(JobLimits.seconds(forType: "create"), 20 * 60)
        XCTAssertEqual(JobLimits.seconds(forType: "helper_update"), 5 * 60)
        XCTAssertEqual(JobLimits.seconds(forType: "start"), OrderFollowing.giveUpAfterSeconds, "a job with no entry keeps the general give-up time")
    }

    func testACreateLimitIsLongerThanTheLongestCreateTheHelperCanTake() {
        XCTAssertGreaterThan(JobLimits.createSeconds, OrderFollowing.longestCreateSeconds)
    }

    func testAJobPastItsLimitIsTimedOutWithAPlainReason() {
        let late = start.addingTimeInterval(TimeInterval(JobLimits.deleteSeconds + 1))
        guard case .timedOut(let reason) = JobWatch.verdict(type: "delete", createdAt: start, now: late, silentPolls: 0, step: JobSteps.backingUp) else { return XCTFail("expected timed out") }
        XCTAssertTrue(reason.contains("30 minutes"))
        XCTAssertTrue(reason.contains(JobSteps.backingUp), "the reason names where it was")
    }

    func testAJobInsideItsLimitKeepsWaiting() {
        XCTAssertEqual(JobWatch.verdict(type: "delete", createdAt: start, now: start.addingTimeInterval(60), silentPolls: 10, step: nil), .keepWaiting)
        XCTAssertEqual(JobWatch.verdict(type: "create", createdAt: start, now: start.addingTimeInterval(TimeInterval(JobLimits.createSeconds)), silentPolls: 0, step: nil), .keepWaiting, "exactly at the limit is still inside it")
    }

    func testASilentMachineGivesLostContactWithTheLastKnownStep() {
        let verdict = JobWatch.verdict(type: "delete", createdAt: start, now: start.addingTimeInterval(400), silentPolls: OrderFollowing.lostContactAfterPolls, step: JobSteps.deleting)
        guard case .lostContact(let reason) = verdict else { return XCTFail("expected lost contact") }
        XCTAssertTrue(reason.contains(JobSteps.deleting))
        guard case .lostContact(let plain) = JobWatch.verdict(type: "start", createdAt: start, now: start, silentPolls: 999, step: nil) else { return XCTFail("expected lost contact") }
        XCTAssertFalse(plain.contains("last step"))
    }

    func testTheLimitBeatsASilentMachine() {
        let late = start.addingTimeInterval(TimeInterval(JobLimits.createSeconds + 5))
        guard case .timedOut = JobWatch.verdict(type: "create", createdAt: start, now: late, silentPolls: 999, step: nil) else { return XCTFail("expected timed out") }
    }

    func testOnlyTheFixedStepNamesAreKnown() {
        for step in JobSteps.all { XCTAssertTrue(JobSteps.isKnown(step)) }
        XCTAssertFalse(JobSteps.isKnown("incus export exited with 1: secret"))
        XCTAssertFalse(JobSteps.isKnown(""))
    }

    func testFinalStates() {
        for state in ["succeeded", "failed", "timed_out", "lost_contact"] { XCTAssertTrue(JobState.isFinal(state)) }
        for state in ["queued", "running"] { XCTAssertFalse(JobState.isFinal(state)) }
    }
}

final class JobNoticeTests: XCTestCase {
    func testEveryFinalStateHasItsOwnKindAndAnythingElseHasNone() {
        let kinds = ["succeeded", "failed", "timed_out", "lost_contact"].compactMap { JobNotice.make(type: "delete", state: $0, machine: "rtx", workload: "vm-1", minutes: 30)?.kind }
        XCTAssertEqual(kinds, ["job_succeeded", "job_failed", "job_timed_out", "job_lost_contact"])
        XCTAssertNil(JobNotice.make(type: "delete", state: "running", machine: "rtx", workload: nil, minutes: 30))
    }

    func testTheTextIsFromTheFixedListWithTheNameAndNoEngineText() {
        let notice = JobNotice.make(type: "delete", state: "failed", machine: "rtx", workload: "vm-1", minutes: 30)
        XCTAssertEqual(notice?.title, "Delete VM failed")
        XCTAssertEqual(notice?.detail, "Delete VM for vm-1 on rtx did not finish. Open the job to see why, then try again.")
    }

    func testControlCharactersAreRemovedAndNamesAreCut() {
        let hostile = "rtx\u{1B}[31m\nINJECT\u{7}" + String(repeating: "x", count: 500)
        let notice = JobNotice.make(type: "create", state: "timed_out", machine: hostile, workload: nil, minutes: 20)
        XCTAssertNotNil(notice)
        let text = (notice?.title ?? "") + (notice?.detail ?? "")
        XCTAssertFalse(text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) })
        XCTAssertLessThanOrEqual(notice?.title.count ?? 999, JobNotice.maxTitle)
        XCTAssertLessThanOrEqual(notice?.detail.count ?? 999, JobNotice.maxDetail)
        XCTAssertLessThanOrEqual(JobNotice.clean(hostile).count, JobNotice.maxName)
    }

    func testAnUnknownJobTypeGetsTheGenericLabel() {
        XCTAssertEqual(JobNotice.make(type: "mystery", state: "succeeded", machine: "m", workload: nil, minutes: 30)?.title, "Job finished")
    }
}

final class NotificationQueryTests: XCTestCase {
    func testDefaultsAndFullQuery() throws {
        XCTAssertEqual(try NotificationQuery.read([]), NotificationQuery())
        let query = try NotificationQuery.read([("page", "3"), ("page_size", "100"), ("unread", "true")])
        XCTAssertEqual([query.page, query.pageSize], [3, 100])
        XCTAssertTrue(query.unreadOnly)
    }

    func testBadQueriesAreRefused() {
        for pairs in [[("page", "0")], [("page_size", "101")], [("page_size", "05")], [("unread", "yes")], [("x", "1")], [("page", "1"), ("page", "2")], [("page", "")]] {
            XCTAssertThrowsError(try NotificationQuery.read(pairs), "\(pairs)")
        }
    }

    func testMarkBodies() throws {
        XCTAssertEqual(try NotificationMark.parse(Data(#"{"all":true}"#.utf8)), .all)
        XCTAssertEqual(try NotificationMark.parse(Data(#"{"ids":[1,2]}"#.utf8)), .ids([1, 2]))
        for bad in [#"{}"#, #"{"all":false}"#, #"{"all":true,"ids":[1]}"#, #"{"ids":[]}"#, #"{"ids":[0]}"#, #"{"ids":["a"]}"#, #"{"ids":[1],"x":1}"#, "nope",
                    "{\"ids\":[" + (1...101).map(String.init).joined(separator: ",") + "]}"] {
            XCTAssertThrowsError(try NotificationMark.parse(Data(bad.utf8)), bad)
        }
    }
}
