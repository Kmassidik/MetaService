import Foundation

/// How many software updates are waiting, from `softwareupdate -l` (slow: it asks Apple's servers). The count is kept for 30 minutes and
/// renewed in the background, so the route never waits for it; until the first answer arrives it is nil. A failed try is repeated after 5 minutes.
public final class PendingUpdates: @unchecked Sendable {
    public static let tool = "/usr/sbin/softwareupdate"
    public static let arguments = ["-l"]
    public static let timeoutSeconds: TimeInterval = 60
    public static let keepSeconds: TimeInterval = 30 * 60
    public static let retrySeconds: TimeInterval = 5 * 60
    static let labelPrefix = "* Label:"

    public typealias Run = @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) async throws -> Data

    private let run: Run
    private let now: @Sendable () -> TimeInterval
    private let lock = NSLock()
    private var count: Int?
    private var nextTry: TimeInterval = -.infinity
    private var refreshing = false

    public init(now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, run: @escaping Run) {
        self.run = run; self.now = now
    }

    /// The last known count. When it is out of date, a refresh starts in the background.
    public func current() -> Int? {
        let (value, due) = state()
        if due { Task.detached { [self] in await refresh() } }
        return value
    }

    /// Asks `softwareupdate` now and keeps the answer.
    public func refresh() async {
        let counted = (try? await run(Self.tool, Self.arguments, Self.timeoutSeconds)).map { Self.count(String(decoding: $0, as: UTF8.self)) }
        finish(counted)
    }

    /// One per `* Label:` line. "No new software available." has none, so it is 0.
    public static func count(_ output: String) -> Int {
        output.split(whereSeparator: \.isNewline).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(labelPrefix) }.count
    }

    private func state() -> (Int?, Bool) {
        lock.lock(); defer { lock.unlock() }
        let due = !refreshing && now() >= nextTry
        refreshing = refreshing || due
        return (count, due)
    }

    private func finish(_ counted: Int?) {
        lock.lock(); defer { lock.unlock() }
        refreshing = false
        count = counted
        nextTry = now() + (counted == nil ? Self.retrySeconds : Self.keepSeconds)
    }
}
