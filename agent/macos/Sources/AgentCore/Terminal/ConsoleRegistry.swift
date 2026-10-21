import Foundation

/// Which workloads have a console open right now. At most one each. Safe to call from any thread.
public final class ConsoleRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var open: [String: @Sendable (ConsoleClose) -> Void] = [:]

    public init() {}

    public func isOpen(_ id: String) -> Bool {
        lock.withLock { open[id] != nil }
    }

    /// True when this caller now holds the workload's console; false when someone else already does.
    /// `onEnd` is called if the workload is stopped or deleted while the console is open.
    public func claim(_ id: String, onEnd: @escaping @Sendable (ConsoleClose) -> Void = { _ in }) -> Bool {
        lock.withLock {
            guard open[id] == nil else { return false }
            open[id] = onEnd
            return true
        }
    }

    public func release(_ id: String) {
        lock.withLock { _ = open.removeValue(forKey: id) }
    }

    /// Tells the console on this workload (if any) why it must close. The holder still calls `release`.
    public func end(_ id: String, _ reason: ConsoleClose) {
        let notify = lock.withLock { open[id] }
        notify?(reason)
    }
}
