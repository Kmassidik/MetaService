import Foundation
import RootCore
import XCTest
@testable import RootStore

final class TeamAndKeyStoreTests: XCTestCase {
    private var database: Database!
    private var teams: TeamStore!
    private var keys: ApiKeyStore!
    private var audit: AuditStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        teams = TeamStore(database)
        keys = ApiKeyStore(database)
        audit = AuditStore(database)
    }

    private func makeTeam(id: String = "team-1", limits: TeamLimits = .standard) throws {
        try teams.create(id: id, name: "Team \(id)", limits: limits, now: now)
    }

    private func storeKey(_ issued: ApiKeyRules.Issued, id: String = "key-1", team: String = "team-1") throws {
        try keys.create(id: id, team: team, prefix: issued.prefix, secretHash: issued.secretHash, now: now)
    }

    func testATeamRoundTripsWithItsLimits() throws {
        let limits = TeamLimits(maxRunning: 3, maxVcpu: 6, maxRamMb: 4_096, maxSandboxesPerHour: 12)
        let made = try teams.create(id: "team-1", name: "Onyenza", limits: limits, now: now)
        XCTAssertEqual(made, TeamRecord(id: "team-1", name: "Onyenza", createdAt: now, limits: limits))
        XCTAssertEqual(try teams.get("team-1"), made)
        XCTAssertEqual(try teams.limits(of: "team-1"), limits)
        XCTAssertEqual(try teams.name(of: "team-1"), "Onyenza")
        XCTAssertEqual(try teams.list(), [made])
    }

    func testAChangedLimitIsReadBack() throws {
        try makeTeam()
        let tighter = TeamLimits(maxRunning: 1, maxVcpu: 2, maxRamMb: 1_024, maxSandboxesPerHour: 5)
        XCTAssertTrue(try teams.setLimits(tighter, team: "team-1"))
        XCTAssertFalse(try teams.setLimits(tighter, team: "nobody"))
        XCTAssertEqual(try teams.limits(of: "team-1"), tighter)
    }

    func testAKeyKeepsOnlyItsPrefixAndHash() throws {
        try makeTeam()
        let issued = ApiKeyRules.issue()
        try storeKey(issued)
        let listed = try keys.list(team: "team-1")
        XCTAssertEqual(listed.map(\.prefix), [issued.prefix])
        XCTAssertNil(listed.first?.lastUsedAt)
        XCTAssertNil(listed.first?.revokedAt)
        let shown = try XCTUnwrap(String(data: try JSONEncoder().encode(listed), encoding: .utf8))
        XCTAssertTrue(shown.contains(issued.prefix))
        XCTAssertFalse(shown.contains(issued.key))
        XCTAssertFalse(shown.contains(issued.secretHash))
        XCTAssertEqual(try keys.find(prefix: issued.prefix)?.secretHash, issued.secretHash)
    }

    func testAGoodKeyIsAcceptedAndItsUseNoted() throws {
        try makeTeam()
        let issued = ApiKeyRules.issue()
        try storeKey(issued)
        let accepted = try keys.authenticate(issued.key, now: now.addingTimeInterval(30))
        XCTAssertEqual(accepted.team, "team-1")
        XCTAssertEqual(accepted.prefix, issued.prefix)
        XCTAssertEqual(try keys.list(team: "team-1").first?.lastUsedAt, now.addingTimeInterval(30))
    }

    func testAWrongSecretIsRefused() throws {
        try makeTeam()
        let issued = ApiKeyRules.issue()
        try storeKey(issued)
        let wrong = ApiKeyRules.text(prefix: issued.prefix, secret: String(repeating: "b", count: ApiKeyRules.secretCharacters))
        XCTAssertThrowsError(try keys.authenticate(wrong, now: now)) {
            XCTAssertEqual(($0 as? ApiKeyRefusal)?.code, ApiKeyCheck.unknownCode)
        }
        XCTAssertNil(try keys.list(team: "team-1").first?.lastUsedAt, "a refused key is not noted as used")
    }

    func testARevokedKeyIsRefusedWithItsOwnReason() throws {
        try makeTeam()
        let issued = ApiKeyRules.issue()
        try storeKey(issued)
        XCTAssertTrue(try keys.revoke(id: "key-1", team: "team-1", now: now))
        XCTAssertThrowsError(try keys.authenticate(issued.key, now: now)) {
            XCTAssertEqual(($0 as? ApiKeyRefusal)?.code, ApiKeyCheck.revokedCode)
        }
        XCTAssertEqual(try keys.list(team: "team-1").first?.revokedAt, now)
    }

    func testRevokingTwiceChangesNothing() throws {
        try makeTeam()
        try storeKey(ApiKeyRules.issue())
        XCTAssertTrue(try keys.revoke(id: "key-1", team: "team-1", now: now))
        XCTAssertFalse(try keys.revoke(id: "key-1", team: "team-1", now: now.addingTimeInterval(60)))
        XCTAssertFalse(try keys.revoke(id: "key-1", team: "other", now: now))
        XCTAssertEqual(try keys.list(team: "team-1").first?.revokedAt, now)
    }

    func testTheAuditEntryForAKeyCarriesThePrefixOnly() throws {
        let issued = ApiKeyRules.issue()
        try audit.record(actor: "operator", action: SandboxAudit.keyCreated, target: "key-1",
                         detail: SandboxAudit.keyDetail(team: "team-1", prefix: issued.prefix), at: now)
        let detail = try XCTUnwrap(try audit.list(limit: 10, before: nil).first?.detail)
        XCTAssertTrue(detail.contains(issued.prefix))
        XCTAssertFalse(detail.contains(issued.key))
        XCTAssertFalse(detail.contains(issued.secretHash))
    }

    func testTheSandboxAuditEntriesSayWhatHappenedAndNeverTheKey() throws {
        let created = SandboxAudit.createDetail(team: "team-1", machine: "m1", template: "base", shape: SandboxShape(), endAt: now.addingTimeInterval(300))
        XCTAssertEqual(created["machine"], "m1")
        XCTAssertEqual(created["vcpu"], "2")
        let ended = SandboxAudit.endDetail(team: "team-1", machine: "m1", reason: .timeout, seconds: 300)
        XCTAssertEqual(ended["reason"], "timeout")
        XCTAssertEqual(ended["seconds"], "300")
        XCTAssertFalse(ended.values.contains { $0.hasPrefix(ApiKeyRules.marker) })
    }
}
