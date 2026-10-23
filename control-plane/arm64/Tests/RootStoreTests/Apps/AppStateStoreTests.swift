import RootCore
import XCTest
@testable import RootStore

final class AppStateStoreTests: XCTestCase {
    private var database: Database!
    private var store: AppStateStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = AppStateStore(database)
    }

    private func want(_ app: String = "openclaw", workload: String = "vm1", machine: String = "mini") throws {
        try store.recordIntent(app: app, workload: workload, machine: machine, now: now)
    }

    func testAVmWithoutAWishHasNoRecord() throws {
        XCTAssertNil(try store.record(workload: "vm1", machine: "mini"))
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now), [])
    }

    func testAWishIsWantedNotStartedAndPendingForTheHeartbeat() throws {
        try want()
        let record = try XCTUnwrap(try store.record(workload: "vm1", machine: "mini"))
        XCTAssertEqual([record.app, record.phase.rawValue], ["openclaw", "none"])
        XCTAssertNil(record.startedAt)
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now), ["vm1"])
    }

    func testBeginningMarksInstallingAndLeavesItAloneForTheHeartbeat() throws {
        try want()
        try store.begin(workload: "vm1", machine: "mini", now: now)
        let record = try XCTUnwrap(try store.record(workload: "vm1", machine: "mini"))
        XCTAssertEqual(record.phase, .installing)
        XCTAssertEqual(record.startedAt, 1_800_000_000)
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now.addingTimeInterval(5)), [])
    }

    func testReadyKeepsVersionAndChecksum() throws {
        try want()
        try store.begin(workload: "vm1", machine: "mini", now: now)
        try store.finish(workload: "vm1", machine: "mini", as: .ready(version: "1.0", installerSha256: "ab"), now: now.addingTimeInterval(60))
        let record = try XCTUnwrap(try store.record(workload: "vm1", machine: "mini"))
        XCTAssertEqual([record.phase.rawValue, record.version, record.installerSha256], ["ready", "1.0", "ab"])
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now.addingTimeInterval(9_999)), [])
    }

    func testAFailureKeepsMessageAndLogAndWaitsItsMinute() throws {
        try want()
        try store.begin(workload: "vm1", machine: "mini", now: now)
        try store.finish(workload: "vm1", machine: "mini", as: .failed(message: "No network", logTail: ["a", "b"]), now: now)
        let record = try XCTUnwrap(try store.record(workload: "vm1", machine: "mini"))
        XCTAssertEqual([record.phase.rawValue, record.message], ["failed", "No network"])
        XCTAssertEqual(record.logTail, ["a", "b"])
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now.addingTimeInterval(59)), [])
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now.addingTimeInterval(60)), ["vm1"])
    }

    func testWaitingPutsTheWishBackToNotStarted() throws {
        try want()
        try store.begin(workload: "vm1", machine: "mini", now: now)
        try store.finish(workload: "vm1", machine: "mini", as: .waiting, now: now)
        XCTAssertEqual(try store.record(workload: "vm1", machine: "mini")?.phase, AppPhase.none)
    }

    func testANewWishForTheSameVmReplacesTheOldState() throws {
        try want()
        try store.finish(workload: "vm1", machine: "mini", as: .failed(message: "x", logTail: ["a"]), now: now)
        try want("hermes")
        let record = try XCTUnwrap(try store.record(workload: "vm1", machine: "mini"))
        XCTAssertEqual([record.app, record.phase.rawValue, record.message ?? "-"], ["hermes", "none", "-"])
        XCTAssertEqual(record.logTail, [])
    }

    func testBeginningWithoutAWishCreatesNothing() throws {
        try store.begin(workload: "vm1", machine: "mini", now: now)
        XCTAssertNil(try store.record(workload: "vm1", machine: "mini"))
    }

    func testForgettingAVmOrAMachineRemovesOnlyTheirRows() throws {
        try want()
        try want(workload: "vm2")
        try want(machine: "dgx")
        try store.forget(workload: "vm1", machine: "mini")
        XCTAssertEqual(Set(try store.records(machine: "mini").keys), ["vm2"])
        try store.forget(machine: "mini")
        XCTAssertTrue(try store.records(machine: "mini").isEmpty)
        XCTAssertEqual(Set(try store.records(machine: "dgx").keys), ["vm1"])
    }

    func testTheListSummaryReadsAnInstallThatNeverEndedAsFailed() throws {
        try want()
        try store.begin(workload: "vm1", machine: "mini", now: now)
        let record = try XCTUnwrap(try store.record(workload: "vm1", machine: "mini"))
        XCTAssertEqual(WorkloadAppSummary(record.atTime(1_800_000_000 + AppRecord.installingTimeoutSeconds)).state, "failed")
        XCTAssertEqual(WorkloadAppSummary(record).state, "installing")
    }

    func testFinishFromAnOutcomeMapsEveryAnswerTheHelperCanGive() {
        XCTAssertEqual(AppFinish(.installed(version: "1", installerSha256: "ab", changed: false)), .ready(version: "1", installerSha256: "ab"))
        XCTAssertEqual(AppFinish(.failed(message: "m", logTail: ["l"])), .failed(message: "m", logTail: ["l"]))
        XCTAssertEqual(AppFinish(.helperTooOld), .failed(message: "This machine's helper is too old for apps. Press Update helper in its Environment tab.", logTail: []))
        XCTAssertEqual(AppFinish(.notDone), .waiting)
        XCTAssertNil(AppFinish.waiting.auditResult)
        XCTAssertEqual(AppFinish.ready(version: nil, installerSha256: "ab").auditResult, "ready")
        XCTAssertEqual(AppFinish.ready(version: nil, installerSha256: "ab").installerSha256, "ab")
        XCTAssertNil(AppFinish.failed(message: "m", logTail: []).installerSha256)
    }
}
