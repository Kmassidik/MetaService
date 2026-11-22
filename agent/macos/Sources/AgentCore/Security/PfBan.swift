import Foundation

/// Bans attacking addresses in the pf table `metaservice_blocklist` through the scoped sudo
/// wrapper `/usr/local/libexec/metaservice-pf` (installed once by Kurnia; see
/// docs/security-model.md). The rules: ≥ `threshold` failed logins from one address within
/// `windowSeconds` → ban for `banSeconds`. An address that only ever fails a couple of times
/// is never touched.
public struct PfBan {
    public static let threshold = 3
    public static let windowSeconds = 600
    public static let banSeconds = 24 * 3600
    public static let wrapper = "/usr/local/libexec/metaservice-pf"

    private let run: Run
    private let now: @Sendable () -> Int
    /// address → the failures inside the current window: (epochs, bannedUntilEpoch or nil).
    private var failures: [String: (epochs: [Int], bannedUntil: Int?)] = [:]

    public typealias Run = @Sendable (_ tool: String, _ arguments: [String], _ timeout: TimeInterval) async throws -> String

    public init(run: @escaping Run, now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.run = run; self.now = now
    }

    /// Feeds one failed attempt and returns a `blocked` event when this attempt crossed the
    /// threshold and the address was newly banned. Everything else returns nil.
    public mutating func failed(address: String?) async -> SecurityEvent? {
        guard let address, !address.isEmpty, isLoopback(address) == false else { return nil }
        let current = now()
        prune(address: address, now: current)
        if await isBanned(address) { return nil }
        var entry = failures[address] ?? (epochs: [], bannedUntil: nil)
        entry.epochs.append(current)
        entry.epochs = entry.epochs.filter { current - $0 <= Self.windowSeconds }
        if entry.epochs.count >= Self.threshold {
            entry.bannedUntil = current + Self.banSeconds
            failures[address] = entry
            await ban(address)
            return SecurityEvent(time: SecurityLogTime.isoNow(), type: .blocked, address: address,
                                 count: entry.epochs.count, until: Self.iso(current + Self.banSeconds))
        }
        failures[address] = entry
        return nil
    }

    /// Whether an address is currently banned: asks pf (the table is the one source of truth,
    /// shared across helper restarts).
    public func isBanned(_ address: String) async -> Bool {
        guard let output = try? await run(Self.wrapper, ["-t", "metaservice_blocklist", "-T", "test", address], 10) else { return false }
        return output.contains("1/1 addresses match")
    }

    private mutating func prune(address: String, now: Int) {
        guard var entry = failures[address] else { return }
        entry.epochs = entry.epochs.filter { now - $0 <= Self.windowSeconds }
        if let until = entry.bannedUntil, until < now { entry.bannedUntil = nil }
        failures[address] = entry
    }

    private func isLoopback(_ address: String) -> Bool {
        address.hasPrefix("127.") || address == "::1" || address.hasPrefix("10.") || address.hasPrefix("192.168.")
    }

    private mutating func ban(_ address: String) async {
        _ = try? await run(Self.wrapper, ["-t", "metaservice_blocklist", "-T", "add", address], 10)
    }

    private static func iso(_ epoch: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}
