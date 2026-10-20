import Foundation

/// How the newest chat command on one machine (or VM) looks, as far as deciding about the next one goes.
public struct BundleCommandFacts: Equatable {
    public let kind: BundleCommandKind
    public let state: String
    public let finishedAt: Date?

    public init(kind: BundleCommandKind, state: String, finishedAt: Date?) {
        self.kind = kind
        self.state = state
        self.finishedAt = finishedAt
    }
}

/// When the parent may start a chat install by itself (to bring a machine to the pinned version). Turning the chat off is the person's wish: it is never undone here.
public enum BundleSchedule {
    public static let retryAfter: TimeInterval = 300

    public static func isDue(last: BundleCommandFacts?, now: Date) -> Bool {
        guard let last else { return true }
        guard last.kind == .install else { return false }
        guard last.state == "failed" else { return last.state == "succeeded" }
        guard let finished = last.finishedAt else { return false }
        return now.timeIntervalSince(finished) > retryAfter
    }
}
