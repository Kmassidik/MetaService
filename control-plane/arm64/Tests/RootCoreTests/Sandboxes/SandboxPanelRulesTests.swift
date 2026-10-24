import Foundation
import MSCore
import RootCore
import XCTest

/// The rules the panel's sandbox routes follow: what a new key keeps, what a team name becomes, which sandbox an action may
/// touch, and how wide the usage window is.
final class SandboxPanelRulesTests: XCTestCase {
    // MARK: keys

    func testANewKeyIsShownAsItsTextAndKeptAsItsPrefixAndHash() throws {
        let made = PanelApiKey.issue()
        let parts = try XCTUnwrap(ApiKeyRules.parse(made.text))
        XCTAssertEqual(made.prefix, parts.prefix)
        XCTAssertEqual(made.secretHash, ApiKeyRules.hash(secret: parts.secret))
        XCTAssertNotEqual(made.secretHash, made.text)
        XCTAssertFalse(made.secretHash.contains(parts.secret))
    }

    func testTheKeptPartsAreEnoughToCheckTheKeyAgain() {
        let made = PanelApiKey.issue()
        let stored = StoredApiKey(id: "key-1", team: "team", prefix: made.prefix, secretHash: made.secretHash, revokedAt: nil)
        guard let parts = ApiKeyRules.parse(made.text) else { return XCTFail("a made key is not one of ours") }
        XCTAssertEqual(ApiKeyGate.check(parts: parts, against: stored), .accepted(stored))
    }

    func testAKeyWhoseSecretWasNotKeptIsRefused() {
        let made = PanelApiKey.issue()
        let other = PanelApiKey.issue()
        let stored = StoredApiKey(id: "key-1", team: "team", prefix: made.prefix, secretHash: other.secretHash, revokedAt: nil)
        guard let parts = ApiKeyRules.parse(made.text) else { return XCTFail("a made key is not one of ours") }
        XCTAssertEqual(ApiKeyGate.check(parts: parts, against: stored), .unknown)
    }

    func testAKeyIdIsTheSameShapeAsEveryOtherId() {
        let id = PanelApiKey.newId()
        XCTAssertTrue(Ids.isValid(id), id)
        XCTAssertTrue(id.hasPrefix("key-"))
        XCTAssertNotEqual(id, PanelApiKey.newId())
    }

    // MARK: team names

    func testATeamNameIsTidiedBeforeItIsKept() {
        XCTAssertEqual(SandboxTeamRules.cleanName("  Oynenza   tasks "), "Oynenza tasks")
        XCTAssertEqual(SandboxTeamRules.cleanName(SandboxTeamRules.defaultTeamName), SandboxTeamRules.defaultTeamName)
        XCTAssertEqual(SandboxTeamRules.cleanName("R&D (lab)"), "R&D (lab)")
        XCTAssertNil(SandboxTeamRules.cleanName("a/b"), "a slash is not shown in a team name")
    }

    func testATeamNameThatIsEmptyOrTooLongIsRefused() {
        XCTAssertNil(SandboxTeamRules.cleanName(""))
        XCTAssertNil(SandboxTeamRules.cleanName("   "))
        XCTAssertNil(SandboxTeamRules.cleanName(String(repeating: "a", count: SandboxTeamRules.nameMax + 1)))
        XCTAssertEqual(SandboxTeamRules.cleanName(String(repeating: "a", count: SandboxTeamRules.nameMax)), String(repeating: "a", count: SandboxTeamRules.nameMax))
    }

    func testATeamIdIsLowercaseLettersDigitsAndDashes() {
        XCTAssertEqual(SandboxTeamRules.id(from: "Oynenza Tasks"), "oynenza-tasks")
        XCTAssertEqual(SandboxTeamRules.id(from: "  two   spaces "), "two-spaces")
        XCTAssertEqual(SandboxTeamRules.id(from: "Ünïcode"), "n-code")
        XCTAssertEqual(SandboxTeamRules.id(from: "!!!"), "team", "an id is never empty")
        XCTAssertEqual(SandboxTeamRules.id(from: "R&D (lab)"), "r-d-lab")
        XCTAssertTrue(Ids.isValid(SandboxTeamRules.id(from: "Our apps")))
    }

    func testALongTeamNameMakesAnIdOfTheLongestSize() {
        let id = SandboxTeamRules.id(from: String(repeating: "a", count: 200))
        XCTAssertEqual(id.count, SandboxTeamRules.idMax)
        XCTAssertTrue(Ids.isValid(id))
    }

    func testANumberedIdStaysTheSameShape() {
        let numbered = SandboxTeamRules.numbered(String(repeating: "a", count: SandboxTeamRules.idMax), 12)
        XCTAssertEqual(numbered.count, SandboxTeamRules.idMax)
        XCTAssertTrue(numbered.hasSuffix("-12"))
        XCTAssertTrue(Ids.isValid(numbered))
    }

    // MARK: usage window

    func testTheUsageWindowDefaultsToAWeekAndRefusesNumbersItCannotMean() {
        XCTAssertEqual(SandboxUsageWindow.days(from: nil), SandboxUsageWindow.defaultDays)
        XCTAssertEqual(SandboxUsageWindow.days(from: 1), 1)
        XCTAssertEqual(SandboxUsageWindow.days(from: SandboxUsageWindow.longestDays), SandboxUsageWindow.longestDays)
        XCTAssertNil(SandboxUsageWindow.days(from: 0))
        XCTAssertNil(SandboxUsageWindow.days(from: -3))
        XCTAssertNil(SandboxUsageWindow.days(from: SandboxUsageWindow.longestDays + 1))
    }

    func testTheWindowStartsWholeDaysBeforeNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SandboxUsageWindow.start(now: now, days: 7), now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(SandboxUsageWindow.start(now: now, days: 0), now)
    }

    // MARK: ownership

    func testATeamMayTouchItsOwnLivingSandboxOnly() {
        XCTAssertTrue(SandboxOwnership.permits(team: "a", sandbox: SandboxOwner(team: "a", state: .running)))
        XCTAssertTrue(SandboxOwnership.permits(team: "a", sandbox: SandboxOwner(team: "a", state: .paused)))
        XCTAssertFalse(SandboxOwnership.permits(team: "b", sandbox: SandboxOwner(team: "a", state: .running)), "another team's sandbox")
        XCTAssertFalse(SandboxOwnership.permits(team: "a", sandbox: SandboxOwner(team: "a", state: .ended)))
    }

    // MARK: the panel's own actions

    func testAnOperatorKillsALivingSandboxAndPausesARunningOne() {
        for state in [SandboxState.starting, .running, .pausing, .resuming, .stopping, .paused] {
            XCTAssertNil(SandboxPanelActions.refusal(.kill, sandbox: SandboxOwner(team: "t", state: state)), state.rawValue)
        }
        for state in [SandboxState.starting, .running, .resuming] {
            XCTAssertNil(SandboxPanelActions.refusal(.pause, sandbox: SandboxOwner(team: "t", state: state)), state.rawValue)
        }
    }

    func testAnEndedSandboxIsNoSuchSandboxForEitherAction() {
        let ended = SandboxOwner(team: "t", state: .ended)
        XCTAssertEqual(SandboxPanelActions.refusal(.kill, sandbox: ended), .noSuchSandbox)
        XCTAssertEqual(SandboxPanelActions.refusal(.pause, sandbox: ended), .noSuchSandbox)
    }

    func testAPausedSandboxIsNotPausedAgain() {
        XCTAssertEqual(SandboxPanelActions.refusal(.pause, sandbox: SandboxOwner(team: "t", state: .paused)), .notPausable)
        XCTAssertEqual(SandboxActionRefusal.notPausable.rawValue, "not_pausable")
        XCTAssertEqual(SandboxActionRefusal.noSuchSandbox.rawValue, "not_found")
    }
}
