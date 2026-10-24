import Foundation
import RootCore
import XCTest
@testable import RootStore

/// The stores behind the panel's sandbox pages: keys across teams, a revoke that is harmless a second time, the live list,
/// and the per-team usage totals.
final class SandboxPanelStoreTests: XCTestCase {
    private var database: Database!
    private var teams: TeamStore!
    private var keys: ApiKeyStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let later = Date(timeIntervalSince1970: 1_800_000_600)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        teams = TeamStore(database)
        keys = ApiKeyStore(database)
        try teams.create(id: "team-a", name: "Team A", now: now)
        try teams.create(id: "team-b", name: "Team B", now: now)
    }

    @discardableResult
    private func addKey(_ id: String, team: String, at when: Date? = nil) throws -> PanelApiKey {
        let made = PanelApiKey.issue()
        try keys.create(id: id, team: team, prefix: made.prefix, secretHash: made.secretHash, now: when ?? now)
        return made
    }

    // MARK: keys

    func testOnlyThePrefixAndTheHashAreStoredAndTheKeyStillChecksOut() throws {
        let made = try addKey("key-1", team: "team-a")
        let stored = try XCTUnwrap(keys.get(id: "key-1"))
        XCTAssertEqual(stored.prefix, made.prefix)
        XCTAssertFalse(stored.prefix.contains(try XCTUnwrap(ApiKeyRules.parse(made.text)).secret))

        let rows = try database.query("SELECT COUNT(*) AS found FROM api_keys WHERE prefix = ? OR secret_hash = ?", [.text(made.text), .text(made.text)])
        XCTAssertEqual(rows.first?.int("found"), 0, "the key text is in no column")

        XCTAssertEqual(try keys.authenticate(made.text, now: later).team, "team-a")
    }

    func testThePanelListsEveryTeamsKeysNewestFirst() throws {
        try addKey("key-old", team: "team-a", at: now)
        try addKey("key-new", team: "team-b", at: later)
        XCTAssertEqual(try keys.listAll().map(\.id), ["key-new", "key-old"])
        XCTAssertEqual(try keys.listAll().map(\.team), ["team-b", "team-a"])
    }

    func testARevokedKeyIsRefusedAndAKeyCannotBeRevokedTwice() throws {
        let made = try addKey("key-1", team: "team-a")
        XCTAssertTrue(try keys.revoke(id: "key-1", team: "team-a", now: later))
        XCTAssertFalse(try keys.revoke(id: "key-1", team: "team-a", now: later), "a second click changes nothing")
        XCTAssertNotNil(try keys.get(id: "key-1")?.revokedAt)
        XCTAssertThrowsError(try keys.authenticate(made.text, now: later)) { error in
            XCTAssertEqual(error as? ApiKeyRefusal, .revoked)
        }
    }

    func testAKeyCannotBeRevokedThroughAnotherTeam() throws {
        try addKey("key-1", team: "team-a")
        XCTAssertFalse(try keys.revoke(id: "key-1", team: "team-b", now: later))
        XCTAssertNil(try keys.get(id: "key-1")?.revokedAt)
    }

    func testATeamIsFoundByItsNameWhateverTheCase() throws {
        XCTAssertEqual(try teams.findByName("team a")?.id, "team-a")
        XCTAssertEqual(try teams.findByName("TEAM B")?.id, "team-b")
        XCTAssertNil(try teams.findByName("Team C"))
    }

    // MARK: the live list

    func testTheLiveListHoldsEveryTeamsLivingSandboxAndLeavesOutTheEnded() throws {
        let sandboxes = SandboxStore(database)
        let limits = TeamLimits(maxRunning: 10, maxVcpu: 100, maxRamMb: 100_000, maxSandboxesPerHour: 100)
        for (id, team) in [("one", "team-a"), ("two", "team-b"), ("three", "team-a")] {
            let new = NewSandbox(id: id, team: team, machine: "m1", template: "base", shape: SandboxShape(), endAt: later, state: .running)
            try sandboxes.create(new, limits: limits, now: now)
        }
        _ = try sandboxes.end(id: "one", at: later, reason: .deleted)
        // Same start time, so the newest-first rule falls back to the id, backwards.
        XCTAssertEqual(try sandboxes.listAlive().map(\.id), ["two", "three"])
    }

    // MARK: usage

    func testTheUsageTableAddsUpEachTeamInTheWindow() throws {
        let usage = SandboxUsageStore(database)
        let shape = SandboxShape(vcpu: 2, ramMb: 512, diskMb: 1_024)
        try usage.record(team: "team-a", sandbox: "one", startedAt: now, endedAt: later, shape: shape)
        try usage.record(team: "team-a", sandbox: "two", startedAt: now, endedAt: now.addingTimeInterval(60), shape: shape)
        try usage.record(team: "team-b", sandbox: "three", startedAt: now, endedAt: now.addingTimeInterval(30), shape: shape)

        let rows = try usage.totalsByTeam(from: now.addingTimeInterval(-60), to: later)
        XCTAssertEqual(rows.map(\.team), ["team-a", "team-b"])
        XCTAssertEqual(rows.first?.sandboxes, 2)
        XCTAssertEqual(rows.first?.totals.seconds, 660)
        XCTAssertEqual(rows.first?.totals.vcpuSeconds, 1_320)
        XCTAssertEqual(rows.first?.totals.ramMbSeconds, 660 * 512)
        XCTAssertEqual(rows.last?.totals.seconds, 30)
    }

    func testTheUsageTableLeavesOutRunsOutsideTheWindow() throws {
        let usage = SandboxUsageStore(database)
        try usage.record(team: "team-a", sandbox: "old", startedAt: now, endedAt: now, shape: SandboxShape())
        XCTAssertTrue(try usage.totalsByTeam(from: later, to: later.addingTimeInterval(60)).isEmpty)
    }
}
