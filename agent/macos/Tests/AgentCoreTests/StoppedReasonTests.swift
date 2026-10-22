import XCTest
@testable import AgentCore

/// What a VM that quit right after it started really printed on the Mac Studio (container 1.1.0, Ubuntu 24.04, systemd as PID 1 without the right to mount /run).
/// The escape sequences are the colours systemd prints; the vminitd lines are the guest agent's own noise.
enum BootLogSample {
    static let esc = "\u{1B}"
    static let boot = """
        vminitd: id: ms-w-old, pid: 70 started managed process
        vminitd: memory threshold exceeded: 91%
        systemd 255.4-1ubuntu8.6 running in system mode
        Failed to mount tmpfs (type tmpfs) on /run (MS_NOSUID|MS_NODEV|MS_STRICTATIME "mode=0755,size=20%,nr_inodes=800k"): Operation not permitted
        vminitd: id: ms-w-old, status: 0 managed process exit
        vminitd: id: ms-w-y7ll5u4, pid: 71 started managed process
        vminitd: memory threshold exceeded: 93%
        Failed to mount tmpfs (type tmpfs) on /run (MS_NOSUID|MS_NODEV|MS_STRICTATIME "mode=0755,size=20%,nr_inodes=800k"): Operation not permitted
        Failed to mount tmpfs (type tmpfs) on /run/lock (MS_NOSUID|MS_NODEV|MS_NOEXEC "mode=1777,size=5242880"): Operation not permitted
        [\(esc)[0;1;31m!!!!!!\(esc)[0m] Failed to mount API filesystems.
        Exiting PID 1...
        vminitd: memory threshold exceeded: 95%
        vminitd: id: ms-w-y7ll5u4, status: 255 managed process exit

        """.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
}

final class StoppedReasonTests: XCTestCase {
    private func reason(exit: Int? = nil, log: String = "", boot: String = BootLogSample.boot) -> StoppedReason {
        StoppedReason.read(exitCode: exit, log: Data(log.utf8), bootLog: Data(boot.utf8))
    }

    func testTheRealBootLogGivesTheLinesOfTheLastStartOnly() {
        let text = reason().logTail
        XCTAssertTrue(text.contains("Failed to mount tmpfs (type tmpfs) on /run/lock"))
        XCTAssertTrue(text.contains("[!!!!!!] Failed to mount API filesystems."))
        XCTAssertTrue(text.contains("Exiting PID 1..."))
        XCTAssertFalse(text.contains("systemd 255.4"), "that line is from an older start of another VM")
        XCTAssertFalse(text.contains("ms-w-old"))
    }

    func testEscapeSequencesAndGuestAgentNoiseAreGone() {
        let text = reason().logTail
        XCTAssertFalse(text.contains(BootLogSample.esc))
        XCTAssertFalse(text.contains("[0;1;31m"))
        XCTAssertFalse(text.contains("memory threshold"))
    }

    func testTheExitCodeComesFromTheToolOrElseFromTheBootLog() {
        XCTAssertEqual(reason().exitCode, 255)
        XCTAssertEqual(reason(exit: 3).exitCode, 3)
        XCTAssertNil(reason(boot: "nothing useful").exitCode)
    }

    func testTheVmsOwnOutputComesBeforeTheBootLinesAndTheTotalIsCapped() {
        let long = (1...40).map { "out \($0)" }.joined(separator: "\n")
        let text = reason(log: long).logTail
        XCTAssertEqual(text.split(separator: "\n").count, StoppedReason.maxLines)
        XCTAssertTrue(text.hasSuffix("status: 255 managed process exit"))
        XCTAssertLessThanOrEqual(text.utf8.count, StoppedReason.maxBytes)
    }

    func testHostileOutputStaysPlainText() {
        let hostile = "<script>alert(1)</script>\u{1B}]0;x\u{07}\u{1B}[2J\u{00}"
        XCTAssertEqual(reason(log: hostile, boot: "").logTail, "<script>alert(1)</script>")
    }

    func testEmptyLogsGiveAnEmptyTail() {
        XCTAssertEqual(reason(boot: "").logTail, "")
    }

    func testItIsSentWithAnExplicitNullExitCode() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = String(decoding: try encoder.encode(StoppedReason(exitCode: nil, logTail: "x")), as: UTF8.self)
        XCTAssertTrue(json.contains("\"exit_code\":null"), json)
        XCTAssertTrue(json.contains("\"log_tail\":\"x\""), json)
    }

    func testInitModesAreOnlyTheTwoWordsTheScriptsWrite() {
        XCTAssertEqual(InitMode.parse("systemd\n"), .systemd)
        XCTAssertEqual(InitMode.parse(" plain "), .plain)
        for bad in ["", "systemd; reboot", "SYSTEMD", "plain\nsystemd", "x"] { XCTAssertNil(InitMode.parse(bad), bad) }
    }

    func testTheFailureMessageNamesBothTries() {
        let exited = StartAttemptFailure.exited(reason())
        let message = StartFailure.message(systemd: exited, plain: .timedOut(seconds: 60))
        XCTAssertTrue(message.hasPrefix("The VM did not start."))
        XCTAssertTrue(message.contains("with systemd: it stopped right after it started (exit code 255)"))
        XCTAssertTrue(message.contains("Failed to mount API filesystems"))
        XCTAssertTrue(message.contains("without systemd: it did not start in time (60 seconds)"))
        XCTAssertFalse(message.contains(BootLogSample.esc))
    }

    func testAContainerThatCouldNotBeStartedAtAllIsSaidInPlainWords() {
        let message = StartFailure.message(systemd: .notStarted, plain: .exited(nil))
        XCTAssertTrue(message.contains("with systemd: the container tool could not start it"))
        XCTAssertTrue(message.contains("without systemd: it stopped right after it started and left no message"))
    }

    func testOnlyAVmThatStoppedByItselfGetsALookAtItsLog() {
        XCTAssertTrue(StoppedReasonPolicy.needsCapture(state: .stopped, stopRequested: false, alreadyKnown: false))
        XCTAssertFalse(StoppedReasonPolicy.needsCapture(state: .stopped, stopRequested: true, alreadyKnown: false), "the panel stopped it")
        XCTAssertFalse(StoppedReasonPolicy.needsCapture(state: .stopped, stopRequested: nil, alreadyKnown: false), "an older record: nobody knows")
        XCTAssertFalse(StoppedReasonPolicy.needsCapture(state: .stopped, stopRequested: false, alreadyKnown: true), "once per stop")
        XCTAssertFalse(StoppedReasonPolicy.needsCapture(state: .running, stopRequested: false, alreadyKnown: false))
    }
}
