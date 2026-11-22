import Foundation
import RootCore
import RootStore

/// The security alerting rules (PRD-security-hardening.md §2): what deserves a notification and
/// what is daily-rate-limited. Runs after each pull, against the events just stored.
public protocol SecurityNotifier: Sendable {
    /// Sends one notification to the operator. `key` rate-limits repeats (once per machine+key+day).
    func send(machine: String, key: String, title: String, detail: String, now: Date) throws
}

public struct SecurityRules {
    /// Failed logins in one hour that count as an attack worth a notification.
    public static let hourlyThreshold = 20

    /// Evaluates the pull's events + the running failed count; returns the notifications to send.
    public static func evaluate(machine: String, events: [SecurityHelperEvent], thresholdCrossed: Bool, now: Date) -> [(key: String, title: String, detail: String)] {
        var out: [(key: String, title: String, detail: String)] = []
        let failed = events.filter { $0.type == .failedLogin }
        // a ban is always worth telling (it means the threshold fired)
        for ban in events.filter({ $0.type == .blocked }) {
            out.append((key: "ban-\(ban.address ?? "?")", title: "Attacker banned on \(machine)",
                        detail: "\(ban.address ?? "?") was banned after \(ban.count) failed logins."))
        }
        // a successful password login on a key-only machine = compromise signal
        for login in events.filter({ $0.type == .login && $0.method == "password" }) {
            out.append((key: "pwlogin-\(login.user ?? "?")-\(login.address ?? "?")",
                        title: "PASSWORD LOGIN on \(machine)",
                        detail: "\(login.user ?? "?") logged in by password from \(login.address ?? "?"). This should never happen."))
        }
        // threshold crossing: the machine's hourly count passed the limit
        if thresholdCrossed {
            let hourFailed = failed.reduce(0) { $0 + $1.count }
            out.append((key: "threshold", title: "Attack rate high on \(machine)",
                        detail: "\(hourFailed) failed logins in the last hour (limit \(hourlyThreshold))."))
        }
        // a brand-new attacking address (never seen before on this machine)
        for address in Set(failed.compactMap({ $0.address })) {
            out.append((key: "newip-\(address)", title: "New attacker on \(machine)",
                        detail: "\(address) failed \(failed.filter { $0.address == address }.map({ $0.count }).reduce(0, +)) logins. Consider adding it to the router blocklist."))
        }
        return out
    }
}

/// The production sender: writes into the root database's notifications for the operator, rate
/// limited by the security_notified table (one per machine+key+day).
public final class DatabaseSecurityNotifier: SecurityNotifier {
    private let database: Database
    public static let recipient = "luca"

    public init(database: Database) { self.database = database }

    public func send(machine: String, key: String, title: String, detail: String, now: Date) throws {
        let day = SecurityTime.day(now)
        try database.execute("""
            INSERT OR IGNORE INTO security_notified (machine, notify_key, day) VALUES (?, ?, ?)
            """, [.text(machine), .text(key), .text(day)])
        let inserted = try database.query("SELECT changes() AS c").first?.int("c") ?? 0
        guard inserted > 0 else { return }
        try database.execute("""
            INSERT INTO notifications (user, kind, title, detail, machine_id, created_at) VALUES (?, ?, ?, ?, ?, ?)
            """, [.text(Self.recipient), .text("security"), .text(title), .text(detail), .text(machine), .int(Int(now.timeIntervalSince1970))])
    }
}
