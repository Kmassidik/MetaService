import RootCore
import XCTest
@testable import RootStore

final class SshKeyStoreTests: XCTestCase {
    private var database: Database!
    private var store: SshKeyStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = SshKeyStore(database)
    }

    private func key(_ number: Int, comment: String = "me") -> ParsedSshKey {
        ParsedSshKey(type: "ssh-ed25519", blob: "blob\(number)", comment: comment, fingerprint: "SHA256:fp\(number)")
    }

    private func add(_ number: Int, id: String? = nil, workload: String = "vm1", machine: String = "mini") throws {
        try store.add(key(number), id: id ?? "key-\(number)", workload: workload, machine: machine, now: now.addingTimeInterval(TimeInterval(number)))
    }

    func testAKeyIsListedWithoutItsBodyAndTheVmIsNotApplied() throws {
        try add(1)
        XCTAssertEqual(try store.list(workload: "vm1", machine: "mini"), [SshKeyRecord(id: "key-1", type: "ssh-ed25519", fingerprint: "SHA256:fp1", comment: "me", addedAt: 1_800_000_001)])
        XCTAssertEqual(try store.state(workload: "vm1", machine: "mini"), SshKeyState(applied: false, sshd: nil))
    }

    func testAVmWithNothingStoredHasNothingPending() throws {
        XCTAssertEqual(try store.state(workload: "vm1", machine: "mini"), SshKeyState(applied: true, sshd: nil))
        XCTAssertEqual(try store.list(workload: "vm1", machine: "mini"), [])
        XCTAssertEqual(try store.snapshot(workload: "vm1", machine: "mini"), SshKeySnapshot(lines: [], revision: 0))
    }

    func testTheSameKeyTwiceOnOneVmIsADuplicateButAnotherVmMayHaveIt() throws {
        try add(1)
        XCTAssertThrowsError(try add(1, id: "key-other")) { XCTAssertEqual($0 as? SshKeyError, .duplicate) }
        try add(1, id: "key-other-vm", workload: "vm2")
        try add(1, id: "key-other-machine", machine: "dgx")
        XCTAssertEqual(try store.list(workload: "vm1", machine: "mini").count, 1)
    }

    func testTheTwentyFirstKeyIsRefusedAndNothingIsChanged() throws {
        for number in 1...SshKeyRules.maxKeysPerVM { try add(number) }
        XCTAssertThrowsError(try add(99)) { XCTAssertEqual($0 as? SshKeyError, .tooMany) }
        XCTAssertEqual(try store.list(workload: "vm1", machine: "mini").count, SshKeyRules.maxKeysPerVM)
        try add(1, id: "other", workload: "vm2")
    }

    func testSnapshotGivesTheNormalisedLinesInTheOrderTheyWereAdded() throws {
        try add(1)
        try add(2)
        try store.add(key(3, comment: ""), id: "key-3", workload: "vm1", machine: "mini", now: now.addingTimeInterval(9))
        let snapshot = try store.snapshot(workload: "vm1", machine: "mini")
        XCTAssertEqual(snapshot.lines, ["ssh-ed25519 blob1 me", "ssh-ed25519 blob2 me", "ssh-ed25519 blob3"])
        XCTAssertEqual(snapshot.revision, 3)
    }

    func testRemovingAKeyReturnsItsFingerprintAndMakesTheVmPendingAgain() throws {
        try add(1)
        try add(2)
        let revision = try store.snapshot(workload: "vm1", machine: "mini").revision
        try store.recordApply(workload: "vm1", machine: "mini", revision: revision, applied: true, sshd: "running")
        XCTAssertEqual(try store.state(workload: "vm1", machine: "mini").applied, true)
        XCTAssertEqual(try store.remove(id: "key-1", workload: "vm1", machine: "mini"), "SHA256:fp1")
        XCTAssertEqual(try store.state(workload: "vm1", machine: "mini"), SshKeyState(applied: false, sshd: "running"))
        XCTAssertEqual(try store.snapshot(workload: "vm1", machine: "mini").lines, ["ssh-ed25519 blob2 me"])
    }

    func testRemovingAnUnknownKeyOrAnotherVmsKeyIsNotFound() throws {
        try add(1)
        XCTAssertThrowsError(try store.remove(id: "nope", workload: "vm1", machine: "mini")) { XCTAssertEqual($0 as? SshKeyError, .notFound) }
        XCTAssertThrowsError(try store.remove(id: "key-1", workload: "vm2", machine: "mini")) { XCTAssertEqual($0 as? SshKeyError, .notFound) }
        XCTAssertThrowsError(try store.remove(id: "key-1", workload: "vm1", machine: "dgx")) { XCTAssertEqual($0 as? SshKeyError, .notFound) }
        XCTAssertEqual(try store.list(workload: "vm1", machine: "mini").count, 1)
    }

    func testAnApplyThatFinishesAfterANewerChangeDoesNotMarkTheVmApplied() throws {
        try add(1)
        let stale = try store.snapshot(workload: "vm1", machine: "mini").revision
        try add(2)
        try store.recordApply(workload: "vm1", machine: "mini", revision: stale, applied: true, sshd: "running")
        XCTAssertEqual(try store.state(workload: "vm1", machine: "mini"), SshKeyState(applied: false, sshd: nil))
        try store.recordApply(workload: "vm1", machine: "mini", revision: try store.snapshot(workload: "vm1", machine: "mini").revision, applied: true, sshd: "installed")
        XCTAssertEqual(try store.state(workload: "vm1", machine: "mini"), SshKeyState(applied: true, sshd: "installed"))
    }

    func testAFailedApplyKeepsWhatSshdSaidBefore() throws {
        try add(1)
        let revision = try store.snapshot(workload: "vm1", machine: "mini").revision
        try store.recordApply(workload: "vm1", machine: "mini", revision: revision, applied: true, sshd: "running")
        try store.recordApply(workload: "vm1", machine: "mini", revision: revision, applied: false, sshd: nil)
        XCTAssertEqual(try store.state(workload: "vm1", machine: "mini"), SshKeyState(applied: false, sshd: "running"))
    }

    func testPendingWorkloadsAreTheOnesOfThatMachineNotYetApplied() throws {
        try add(1, workload: "vm1")
        try add(2, workload: "vm2")
        try add(3, workload: "vm3", machine: "dgx")
        try store.recordApply(workload: "vm2", machine: "mini", revision: 1, applied: true, sshd: "running")
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now), ["vm1"])
        XCTAssertEqual(try store.pendingWorkloads(machine: "dgx", now: now), ["vm3"])
    }

    func testForgettingAVmRemovesItsKeysAndStateButNotAnotherVms() throws {
        try add(1, workload: "vm1")
        try add(2, workload: "vm2")
        try store.forget(workload: "vm1", machine: "mini")
        XCTAssertEqual(try store.list(workload: "vm1", machine: "mini"), [])
        XCTAssertEqual(try store.state(workload: "vm1", machine: "mini").applied, true)
        XCTAssertEqual(try store.list(workload: "vm2", machine: "mini").count, 1)
    }

    func testRemovingAMachineRemovesItsVmsKeys() throws {
        try MachineStore(database).enroll(name: "mini", tokenHash: "h", commandTokenSealed: "s", ip: nil, now: now)
        try add(1)
        try add(2, workload: "vm9", machine: "dgx")
        try MachineStore(database).remove(id: "mini")
        XCTAssertEqual(try store.list(workload: "vm1", machine: "mini"), [])
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now), [])
        XCTAssertEqual(try store.list(workload: "vm9", machine: "dgx").count, 1)
    }

    // MARK: progress of setting up the SSH server

    func testAVmNobodyTouchedIsIdleAndABeginMakesItInstalling() throws {
        XCTAssertEqual(try store.progress(workload: "vm1", machine: "mini"), .idle)
        try store.beginApply(workload: "vm1", machine: "mini", now: now)
        XCTAssertEqual(try store.progress(workload: "vm1", machine: "mini"), SshdProgress(phase: .installing, message: nil, since: 1_800_000_000))
    }

    func testFinishingClearsTheInstallingPhaseOrKeepsTheReason() throws {
        try add(1)
        try store.beginApply(workload: "vm1", machine: "mini", now: now)
        try store.finishApply(workload: "vm1", machine: "mini", failure: nil, now: now)
        XCTAssertEqual(try store.progress(workload: "vm1", machine: "mini"), .idle)
        try store.beginApply(workload: "vm1", machine: "mini", now: now)
        try store.finishApply(workload: "vm1", machine: "mini", failure: "No internet.", now: now)
        XCTAssertEqual(try store.progress(workload: "vm1", machine: "mini"), SshdProgress(phase: .failed, message: "No internet.", since: 1_800_000_000))
        XCTAssertEqual(try store.snapshot(workload: "vm1", machine: "mini").lines.count, 1, "progress never touches the keys")
    }

    func testTheHeartbeatSkipsARunningApplyAndAFreshFailureButTakesAnOldOne() throws {
        try add(1, workload: "vm1")
        try add(2, workload: "vm2")
        try add(3, workload: "vm3")
        try store.beginApply(workload: "vm1", machine: "mini", now: now)
        try store.finishApply(workload: "vm2", machine: "mini", failure: "x", now: now)
        try store.finishApply(workload: "vm3", machine: "mini", failure: "x", now: now.addingTimeInterval(-TimeInterval(SshdProgress.retryWaitSeconds)))
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now), ["vm3"])
        let later = now.addingTimeInterval(TimeInterval(SshdProgress.retryWaitSeconds))
        XCTAssertEqual(Set(try store.pendingWorkloads(machine: "mini", now: later)), ["vm2", "vm3"])
        let abandoned = now.addingTimeInterval(TimeInterval(SshdProgress.installingTimeoutSeconds + SshdProgress.retryWaitSeconds))
        XCTAssertEqual(Set(try store.pendingWorkloads(machine: "mini", now: abandoned)), ["vm1", "vm2", "vm3"], "an apply that died is tried again")
    }

    func testBeginningAnApplyForAVmWithoutRowsCreatesAnUnappliedRow() throws {
        try store.beginApply(workload: "vm7", machine: "mini", now: now)
        XCTAssertEqual(try store.pendingWorkloads(machine: "mini", now: now.addingTimeInterval(TimeInterval(SshdProgress.installingTimeoutSeconds + SshdProgress.retryWaitSeconds))), ["vm7"])
    }
}
