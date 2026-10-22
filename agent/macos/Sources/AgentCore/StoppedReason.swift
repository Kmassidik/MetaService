import Foundation
import MSCore

/// Why a VM stopped by itself: the exit code when it is known, and the last lines the VM printed.
/// Everything in `logTail` came from inside the VM, so it is text only: escape sequences and control characters are gone and the size is capped.
public struct StoppedReason: Equatable, Encodable {
    public static let maxLines = 12
    public static let maxBytes = 2048
    private static let startedMarker = "started managed process"
    private static let guestAgentNoise = "memory threshold"
    private static let exitPattern = #/status: (\d{1,3}) managed process exit/#

    public let exitCode: Int?
    public let logTail: String

    public init(exitCode: Int?, logTail: String) {
        self.exitCode = exitCode
        self.logTail = logTail
    }

    enum CodingKeys: String, CodingKey { case exitCode, logTail }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(exitCode, forKey: .exitCode)
        try box.encode(logTail, forKey: .logTail)
    }

    /// Builds the reason from the VM's own output and from the boot log of the tiny VM it runs in. Only the lines of the last start count in the boot log.
    public static func read(exitCode: Int?, log: Data, bootLog: Data) -> StoppedReason {
        let boot = lastStart(String(decoding: bootLog, as: UTF8.self))
        let lines = quiet(String(decoding: log, as: UTF8.self)) + quiet(boot)
        return StoppedReason(exitCode: exitCode ?? exitCodeInBootLog(boot),
                             logTail: UntrustedText.tail(lines.joined(separator: "\n"), lines: maxLines, maxBytes: maxBytes))
    }

    private static func lastStart(_ boot: String) -> String {
        let lines = boot.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.lastIndex(where: { $0.contains(startedMarker) }) else { return boot }
        return lines[(start + 1)...].joined(separator: "\n")
    }

    /// The guest agent warns about its own memory now and then. That is not the VM's message.
    private static func quiet(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.contains(guestAgentNoise) }
    }

    private static func exitCodeInBootLog(_ boot: String) -> Int? {
        boot.matches(of: exitPattern).last.flatMap { Int($0.output.1) }
    }
}

/// How a VM was started: with systemd as its first process, or plain (a process that only keeps it alive, so a terminal works but services do not).
public enum InitMode: String, Codable, Equatable {
    case systemd, plain

    /// What the start script wrote into the VM for the helper to read back. Anything but exactly one of the two words is not an answer.
    public static func parse(_ text: String) -> InitMode? {
        InitMode(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// How one try at starting a VM ended badly.
public enum StartAttemptFailure: Equatable {
    case exited(StoppedReason?)
    case timedOut(seconds: Int)
    case notStarted
}

/// The plain-words message for a create that failed in both modes.
public enum StartFailure {
    public static func message(systemd: StartAttemptFailure, plain: StartAttemptFailure) -> String {
        ["The VM did not start.", line(1, "with systemd", systemd), line(2, "without systemd", plain)].joined(separator: "\n")
    }

    private static func line(_ number: Int, _ label: String, _ failure: StartAttemptFailure) -> String {
        "Try \(number), \(label): \(sentence(failure))"
    }

    private static func sentence(_ failure: StartAttemptFailure) -> String {
        switch failure {
        case .notStarted: return "the container tool could not start it."
        case .timedOut(let seconds): return "it did not start in time (\(seconds) seconds)."
        case .exited(let reason): return "it stopped right after it started" + describe(reason)
        }
    }

    private static func describe(_ reason: StoppedReason?) -> String {
        guard let reason else { return " and left no message." }
        let code = reason.exitCode.map { " (exit code \($0))" } ?? ""
        return reason.logTail.isEmpty ? code + " and left no message." : code + ". Its last lines:\n" + reason.logTail
    }
}

/// When the helper looks at a stopped VM's log. Only a VM that stopped by itself is worth it, and only once per stop.
public enum StoppedReasonPolicy {
    /// `stopRequested` is nil for a VM made before the helper kept this note: nobody knows, so nothing is guessed.
    public static func needsCapture(state: WorkloadState, stopRequested: Bool?, alreadyKnown: Bool) -> Bool {
        state == .stopped && stopRequested == false && !alreadyKnown
    }
}
