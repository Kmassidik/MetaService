import Foundation

/// One VERBOSE sshd line that carries an attempt or a login: when, which process, user, address.
/// Mirrors the Linux parser's shapes (agent/linux/src/security/parse.rs); see docs/security-model.md §5.
public struct VerboseSighting: Equatable, Sendable {
    public init(epoch: Int, pid: Int, user: String?, address: String?, failed: Bool, method: String?) {
        self.epoch = epoch; self.pid = pid; self.user = user; self.address = address; self.failed = failed; self.method = method
    }
    public let epoch: Int
    public let pid: Int
    public let user: String?
    public let address: String?
    /// true for a failed attempt, false for a successful login.
    public let failed: Bool
    /// "password", "publickey", "keyboard-interactive"… nil when the line does not say.
    public let method: String?
}

/// Parses the compact `log show` text with VERBOSE sshd lines. Lines without a timestamp or a
/// `sshd-session[pid]` prefix are skipped, like the old connection reader did.
public enum SshVerboseLog {
    /// `log show` prints times as `2026-11-01 14:23:06.234` in the machine's own zone.
    static let timeLength = 19

    public static func parse(_ text: String, zone: TimeZone) -> [VerboseSighting] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line($0, zone: zone) }
    }

    private static func line(_ line: Substring, zone: TimeZone) -> VerboseSighting? {
        guard let (epoch, pid) = prefix(line, zone: zone) else { return nil }
        let message = line.dropFirst(timeLength)
        return attempt(epoch: epoch, pid: pid, message: message) ?? login(epoch: epoch, pid: pid, message: message)
    }

    private static func prefix(_ line: Substring, zone: TimeZone) -> (Int, Int)? {
        guard let epoch = SecurityLogTime.epoch(of: String(line.prefix(timeLength)), zone: zone) else { return nil }
        let rest = line.dropFirst(timeLength)
        let marker = "sshd-session["
        for word in rest.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true).prefix(4) where word.hasPrefix(marker) {
            let inside = word.dropFirst(marker.count).prefix { $0 != ":" && $0 != "]" }
            if let pid = Int(inside) { return (epoch, pid) }
        }
        return nil
    }

    /// `Failed password for (invalid user )?u from a port p (ssh2)?` and `Invalid user u from a( port p)?`,
    /// plus the preauth closes and the max-tries line the Linux parser also counts.
    private static func attempt(epoch: Int, pid: Int, message: Substring) -> VerboseSighting? {
        for shape in attemptShapes {
            guard let match = shape.firstMatch(in: message) else { continue }
            return VerboseSighting(epoch: epoch, pid: pid, user: match["user"], address: match["address"], failed: true, method: nil)
        }
        return nil
    }

    /// `Accepted (publickey|password|…) for u from a port p ssh2: …`
    private static func login(epoch: Int, pid: Int, message: Substring) -> VerboseSighting? {
        guard let range = message.range(of: "Accepted ") else { return nil }
        let rest = message[range.upperBound...]
        let parts = rest.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 6 else { return nil }
        let method = String(parts[0])
        let user = String(parts[2])
        let address = String(parts[4])
        return VerboseSighting(epoch: epoch, pid: pid, user: user, address: address, failed: false, method: method)
    }
}

private let attemptShapes: [NSRegularExpression] = {
    let shapes = [
        #"Failed \S+ for (?:invalid user )?(?<user>\S+) from (?<address>\S+) port (?<port>\d+)"#,
        #"Invalid user (?<user>\S*) from (?<address>\S+)(?: port (?<port>\d+))?"#,
        #"(?:Connection closed by|Disconnected from) (?:invalid|authenticating) user (?<user>\S+) (?<address>\S+) port (?<port>\d+).*\[preauth\]"#,
        #"maximum authentication attempts exceeded for (?:invalid user )?(?<user>\S+) from (?<address>\S+) port (?<port>\d+)"#,
    ]
    return shapes.compactMap { try? NSRegularExpression(pattern: $0) }
}()

/// Parses the message-only lines of an `sshd -E` file (no timestamps, no pid). One event per
/// unique (user, address) — the two lines of one connection deduplicate to it.
public extension SshVerboseLog {
    struct ClassicSighting: Equatable {
        public let user: String?
        public let address: String?
        public let failed: Bool
        public let pid: Int
    }

    static let classicShapes: [NSRegularExpression] = {
        let shapes = [
            #"Failed password for (?:invalid user )?(?<user>\S+) from (?<address>\S+) port"#,
            #"Invalid user (?<user>\S*) from (?<address>\S+)(?: port)?"#,
            #"(?:Connection closed by|Disconnected from) (?:invalid |authenticating )?user (?<user>\S+) (?<address>\S+) port"#,
        ]
        return shapes.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    static func parseClassicLines(_ text: String) -> [ClassicSighting] {
        var events: [ClassicSighting] = []
        var seenConnections: Set<String> = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            for shape in classicShapes {
                guard let match = shape.firstMatchValueDict(in: line) else { continue }
                let user = match["user"]
                let address = match["address"]
                let key = "\(user ?? "-")@\(address ?? "-")"
                guard !seenConnections.contains(key) else { continue }
                seenConnections.insert(key)
                events.append(ClassicSighting(user: user, address: address, failed: true, pid: events.count))
                break
            }
        }
        return events
    }
}

extension NSRegularExpression {
    fileprivate func firstMatchValueDict(in text: String) -> [String: String]? {
        guard let match = firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var groups: [String: String] = [:]
        for name in ["user", "address"] {
            let range = match.range(withName: name)
            if range.location != NSNotFound, let swift = Range(range, in: text) { groups[name] = String(text[swift]) }
        }
        return groups
    }

    fileprivate func firstMatchValue(for name: String, in text: Substring) -> String? {
        guard let match = firstMatch(in: String(text), range: NSRange(text.startIndex..., in: text)) else { return nil }
        let range = match.range(withName: name)
        guard range.location != NSNotFound, let swift = Range(range, in: text) else { return nil }
        return String(text[swift])
    }

    fileprivate func firstMatch(in text: Substring) -> [String: String]? {
        guard let match = firstMatch(in: String(text), range: NSRange(text.startIndex..., in: text)) else { return nil }
        var groups: [String: String] = [:]
        for name in ["user", "address"] {
            let range = match.range(withName: name)
            if range.location != NSNotFound, let swift = Range(range, in: text) { groups[name] = String(text[swift]) }
        }
        return groups
    }
}
