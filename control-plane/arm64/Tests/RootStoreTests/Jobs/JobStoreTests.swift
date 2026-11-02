import XCTest
import RootCore
@testable import RootStore

final class JobStoreTests: XCTestCase {
    private var database: Database!
    private var commands: CommandStore!
    private var notifications: NotificationStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        try MachineStore(database).enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed-secret", ip: "10.0.0.5", now: now)
        commands = CommandStore(database)
        notifications = NotificationStore(database)
    }

    private func job(_ id: String, type: String = "delete", actor: String = "kurnia", workload: String? = "w-1") throws {
        try commands.create(id: id, machine: "mini", workloadId: workload, type: type, params: [:], actor: actor, now: now)
        try commands.update(id: id, state: "running", result: nil, now: now)
    }

    // MARK: steps

    func testAStepIsStoredWithItsTimeAndReadBack() throws {
        try job("d-1")
        XCTAssertNil(try commands.get("d-1")?.step, "a new job has no step")
        try commands.setStep(id: "d-1", step: JobSteps.backingUp, now: now.addingTimeInterval(5))
        let row = try XCTUnwrap(try commands.get("d-1"))
        XCTAssertEqual(row.step, JobSteps.backingUp)
        XCTAssertNotNil(row.stepAt)
        let json = String(data: try JSONEncoder().encode(row), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"step\":\"Backing up"))
    }

    func testTextThatIsNotAFixedStepNameIsIgnored() throws {
        try job("d-1")
        try commands.setStep(id: "d-1", step: "incus export exited with 1: /Users/x/secret", now: now)
        XCTAssertNil(try commands.get("d-1")?.step)
    }

    func testAnUnchangedStepKeepsItsFirstTime() throws {
        try job("d-1")
        try commands.setStep(id: "d-1", step: JobSteps.deleting, now: now)
        let first = try commands.get("d-1")?.stepAt
        try commands.setStep(id: "d-1", step: JobSteps.deleting, now: now.addingTimeInterval(60))
        XCTAssertEqual(try commands.get("d-1")?.stepAt, first)
    }

    func testAnEndedJobKeepsItsLastStepAndTakesNoMore() throws {
        try job("d-1")
        try commands.setStep(id: "d-1", step: JobSteps.backingUp, now: now)
        try commands.update(id: "d-1", state: "failed", result: ["error": "x"], now: now)
        try commands.setStep(id: "d-1", step: JobSteps.done, now: now)
        XCTAssertEqual(try commands.get("d-1")?.step, JobSteps.backingUp)
    }

    func testRowsFromBeforeStepsExistedStillRead() throws {
        try database.execute("INSERT INTO commands (id, machine_id, workload_id, type, params_json, state, actor, created_at) VALUES ('old', 'mini', NULL, 'start', '{}', 'succeeded', 'k', 5)")
        let row = try XCTUnwrap(try commands.get("old"))
        XCTAssertNil(row.step)
        XCTAssertNil(row.stepAt)
        XCTAssertEqual(row.state, "succeeded")
    }

    // MARK: end states

    func testTheTwoNewEndStatesAreFinalAndHaveAFinishTime() throws {
        for (id, state) in [("a", "timed_out"), ("b", "lost_contact")] {
            try job(id)
            try commands.update(id: id, state: state, result: ["error": "plain"], now: now.addingTimeInterval(9))
            let row = try XCTUnwrap(try commands.get(id))
            XCTAssertEqual(row.state, state)
            XCTAssertNotNil(row.finishedAt)
        }
        XCTAssertTrue(try commands.unfinished().isEmpty, "a closed job is never listed as unfinished again")
    }

    func testALateAnswerCannotReopenOrChangeAnEndedJob() throws {
        try job("d-1")
        XCTAssertTrue(try commands.update(id: "d-1", state: "timed_out", result: ["error": "slow"], now: now))
        XCTAssertFalse(try commands.update(id: "d-1", state: "succeeded", result: nil, now: now))
        XCTAssertEqual(try commands.get("d-1")?.state, "timed_out")
        XCTAssertEqual(try notifications.page(user: "kurnia", page: 1, pageSize: 10, unreadOnly: false).total, 1, "one job, one notification")
    }

    func testAnOrphanThatWasRunningCanBeListedAndClosed() throws {
        try job("d-1")
        try commands.create(id: "q-1", machine: "mini", workloadId: nil, type: "create", params: [:], actor: "kurnia", now: now)
        XCTAssertEqual(Set(try commands.unfinished().map(\.id)), ["d-1", "q-1"])
        try commands.update(id: "q-1", state: "failed", result: ["error": "never received"], now: now)
        try commands.update(id: "d-1", state: "lost_contact", result: ["error": "silent"], now: now)
        XCTAssertTrue(try commands.unfinished().isEmpty)
    }

    func testASecondDeleteIsSeenWhileOneIsUnfinished() throws {
        try job("d-1")
        XCTAssertEqual(try commands.unfinishedDelete(machine: "mini", workloadId: "w-1")?.id, "d-1")
        try commands.update(id: "d-1", state: "timed_out", result: nil, now: now)
        XCTAssertNil(try commands.unfinishedDelete(machine: "mini", workloadId: "w-1"), "a timed out delete can be sent again")
    }

    // MARK: notifications

    func testEveryEndStateMakesOneNotificationForTheActorOnly() throws {
        let ends = [("succeeded", "job_succeeded"), ("failed", "job_failed"), ("timed_out", "job_timed_out"), ("lost_contact", "job_lost_contact")]
        for (index, (state, _)) in ends.enumerated() {
            try job("j-\(index)", actor: "kurnia")
            try commands.update(id: "j-\(index)", state: state, result: nil, now: now.addingTimeInterval(TimeInterval(index)))
        }
        let page = try notifications.page(user: "kurnia", page: 1, pageSize: 10, unreadOnly: false)
        XCTAssertEqual(page.rows.map(\.kind), ends.map(\.1).reversed(), "newest first")
        XCTAssertEqual(page.unreadCount, 4)
        XCTAssertEqual(page.rows.first?.commandId, "j-3")
        XCTAssertEqual(try notifications.page(user: "luca", page: 1, pageSize: 10, unreadOnly: false).total, 0)
    }

    func testAJobThatIsStillRunningMakesNoNotification() throws {
        try job("d-1")
        XCTAssertEqual(try notifications.page(user: "kurnia", page: 1, pageSize: 10, unreadOnly: false).total, 0)
    }

    func testOneUserNeverSeesOrMarksAnotherUsersRows() throws {
        try job("a", actor: "kurnia")
        try job("b", actor: "luca")
        try commands.update(id: "a", state: "succeeded", result: nil, now: now)
        try commands.update(id: "b", state: "failed", result: nil, now: now)
        let luca = try notifications.page(user: "luca", page: 1, pageSize: 10, unreadOnly: false)
        XCTAssertEqual(luca.rows.map(\.commandId), ["b"])
        let kurniaId = try XCTUnwrap(try notifications.page(user: "kurnia", page: 1, pageSize: 10, unreadOnly: false).rows.first?.id)
        XCTAssertEqual(try notifications.markRead(user: "luca", ids: [kurniaId], now: now), 0, "someone else's id is skipped")
        XCTAssertEqual(try notifications.unreadCount(user: "kurnia"), 1)
        XCTAssertEqual(try notifications.markAllRead(user: "luca", now: now), 1)
        XCTAssertEqual(try notifications.unreadCount(user: "kurnia"), 1, "mark all touches only the caller's rows")
        XCTAssertEqual(try notifications.unreadCount(user: "luca"), 0)
    }

    func testPagingUnreadFilterAndMarkRead() throws {
        for index in 0..<5 {
            try job("j-\(index)")
            try commands.update(id: "j-\(index)", state: "succeeded", result: nil, now: now.addingTimeInterval(TimeInterval(index)))
        }
        let first = try notifications.page(user: "kurnia", page: 1, pageSize: 2, unreadOnly: false)
        XCTAssertEqual(first.rows.map(\.commandId), ["j-4", "j-3"])
        XCTAssertEqual([first.total, first.unreadCount], [5, 5])
        XCTAssertEqual(try notifications.page(user: "kurnia", page: 3, pageSize: 2, unreadOnly: false).rows.map(\.commandId), ["j-0"])
        XCTAssertEqual(try notifications.markRead(user: "kurnia", ids: [first.rows[0].id, first.rows[0].id], now: now), 1, "a repeated id counts once")
        let unread = try notifications.page(user: "kurnia", page: 1, pageSize: 10, unreadOnly: true)
        XCTAssertEqual([unread.total, unread.unreadCount, unread.rows.count], [4, 4, 4])
        let all = try notifications.page(user: "kurnia", page: 1, pageSize: 10, unreadOnly: false)
        XCTAssertEqual([all.total, all.unreadCount], [5, 4], "total follows the filter, the bell count does not")
        XCTAssertNotNil(all.rows[0].readAt)
        XCTAssertEqual(try notifications.page(user: "kurnia", page: 1, pageSize: 5000, unreadOnly: false).rows.count, 5, "page size is capped at 100")
    }

    func testRetentionDeletesNotificationsAndFinishedJobsAfterThirtyDays() throws {
        try job("old")
        try commands.update(id: "old", state: "succeeded", result: nil, now: now)
        try job("fresh")
        try commands.update(id: "fresh", state: "failed", result: nil, now: now.addingTimeInterval(31 * 86_400))
        try job("busy")
        let later = now.addingTimeInterval(32 * 86_400)
        XCTAssertEqual(try notifications.prune(now: later), 1)
        XCTAssertEqual(try notifications.page(user: "kurnia", page: 1, pageSize: 10, unreadOnly: false).rows.map(\.commandId), ["fresh"])
        XCTAssertEqual(try commands.pruneFinished(before: later.addingTimeInterval(-30 * 86_400)), 1)
        XCTAssertNil(try commands.get("old"))
        XCTAssertNotNil(try commands.get("fresh"))
        XCTAssertNotNil(try commands.get("busy"), "an unfinished job is never pruned")
    }

    func testTheMigrationAddsTheColumnsAndTheTable() throws {
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS n FROM notifications").first?.int("n"), 0)
        XCTAssertEqual(try database.query("SELECT MAX(version) AS v FROM schema_version").first?.int("v"), Migrations.latest)
        XCTAssertGreaterThanOrEqual(Migrations.latest, 31)
    }
}
