import Foundation

/// Counts hits per key inside a window. Used for login, enrollment and bad-token lockout.
public final class Throttle: @unchecked Sendable {
    private struct Window { var count: Int; var until: Date }
    private let clock: Clock
    private let maxKeys: Int
    private let lock = NSLock()
    private var windows: [String: Window] = [:]

    public init(clock: Clock = SystemClock(), maxKeys: Int = 10_000) {
        self.clock = clock
        self.maxKeys = maxKeys
    }

    /// True while the key is under `limit` hits in the current `seconds` window. Counts this hit.
    public func allow(_ key: String, limit: Int, seconds: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = clock.now
        dropExpired(now)
        guard var window = windows[key], window.until > now else { return open(key, seconds, now) }
        guard window.count < limit else { return false }
        window.count += 1
        windows[key] = window
        return true
    }

    /// True when the key already used up its `limit` in the current window. Does not count a hit.
    public func isFull(_ key: String, limit: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let window = windows[key], window.until > clock.now else { return false }
        return window.count >= limit
    }

    private func open(_ key: String, _ seconds: TimeInterval, _ now: Date) -> Bool {
        guard windows.count < maxKeys else { return false }
        windows[key] = Window(count: 1, until: now.addingTimeInterval(seconds))
        return true
    }

    private func dropExpired(_ now: Date) {
        guard windows.count > maxKeys / 2 else { return }
        windows = windows.filter { $0.value.until > now }
    }
}
