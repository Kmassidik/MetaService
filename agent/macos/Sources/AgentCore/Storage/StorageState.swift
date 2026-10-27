import Foundation

public final class StorageCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: UInt64 = 0
    private var bytes: UInt64 = 0

    public init() {}

    public func reset() {
        lock.lock()
        entries = 0
        bytes = 0
        lock.unlock()
    }

    public func addEntry(bytes: UInt64) {
        lock.lock()
        entries += 1
        self.bytes += bytes
        lock.unlock()
    }

    public func addEntry() { addEntry(bytes: 0) }

    public func snapshot() -> StorageProgress {
        lock.lock()
        defer { lock.unlock() }
        return StorageProgress(entries: entries, bytes: bytes)
    }
}

/// Running scan state: coalesces concurrent/cooldown requests and always retains the last good map.
public final class StorageState: @unchecked Sendable {
    public typealias Completion = @Sendable (Result<StorageMap, StorageScanFailure>) -> Void
    public typealias Start = @Sendable (@escaping Completion) -> Void

    private let lock = NSLock()
    private let counters: StorageCounters
    private let start: Start
    private let now: @Sendable () -> TimeInterval
    private let cooldown: TimeInterval
    private let persist: (@Sendable (StorageMap) throws -> Void)?
    private var scanning = false
    private var ended: TimeInterval?
    private var error: String?
    private var map: StorageMap?

    public init(counters: StorageCounters = StorageCounters(), cooldown: TimeInterval = 30,
                now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                restored: StorageMap? = nil, persist: (@Sendable (StorageMap) throws -> Void)? = nil,
                start: @escaping Start) {
        self.counters = counters
        self.cooldown = cooldown
        self.now = now
        self.persist = persist
        self.map = restored
        self.start = start
    }

    public func answer() -> StorageAnswer {
        lock.lock()
        defer { lock.unlock() }
        let progress = scanning ? counters.snapshot() : nil
        return StorageAnswer(scanning: scanning, progress: progress, error: error, map: map)
    }

    /// Starts the initial scan only when no map was restored and no earlier scan has finished.
    public func startIfNeeded() -> StorageAnswer {
        lock.lock()
        let shouldStart = map == nil && !scanning && ended == nil
        if shouldStart {
            scanning = true
            counters.reset()
        }
        lock.unlock()
        guard shouldStart else { return answer() }
        return begin()
    }

    /// Starts at most one scan. Repeated posts and posts within 30 seconds of completion return the current answer.
    public func scan() -> StorageAnswer {
        lock.lock()
        let rested = ended.map { now() - $0 >= cooldown } ?? true
        let shouldStart = !scanning && rested
        if shouldStart {
            scanning = true
            counters.reset()
        }
        lock.unlock()
        guard shouldStart else { return answer() }
        return begin()
    }

    private func begin() -> StorageAnswer {
        start { [weak self] result in
            switch result {
            case .success(let map): self?.finish(map)
            case .failure(let failure): self?.fail(failure.message)
            }
        }
        return answer()
    }

    private func finish(_ completed: StorageMap) {
        lock.lock()
        scanning = false
        ended = now()
        map = completed
        error = nil
        lock.unlock()
        do {
            try persist?(completed)
        } catch {
            lock.lock()
            self.error = String("the map could not be saved: \(error)".prefix(300))
            lock.unlock()
        }
    }

    private func fail(_ message: String) {
        lock.lock()
        scanning = false
        ended = now()
        error = String(message.prefix(300))
        lock.unlock()
    }
}
