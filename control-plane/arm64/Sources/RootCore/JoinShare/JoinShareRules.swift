import Foundation

/// What a panel request to /api/join-share/... turns into: the hub path to call, and what to write in the audit log.
public struct JoinShareCall: Equatable {
    public let method: String
    /// The hub's own path (`/admin/...`), built here from the allow-list. It never contains anything else the browser sent.
    public let hubPath: String
    /// Set for the four writes that are audited: `join_share.link`, `.approve`, `.refuse`, `.remove`.
    public let auditAction: String?
    /// The pending id or the peer name. A link has none (see `linkTarget`).
    public let auditTarget: String?

    public init(method: String, hubPath: String, auditAction: String? = nil, auditTarget: String? = nil) {
        self.method = method
        self.hubPath = hubPath
        self.auditAction = auditAction
        self.auditTarget = auditTarget
    }
}

public enum JoinShareMatch: Equatable {
    /// `GET /api/join-share/status`: answered by the parent itself.
    case status
    case hub(JoinShareCall)
}

/// The rules of the Share a PC proxy: which method and path pairs the panel may use, which ids and names may go into a hub path, and the limits.
/// Pure, so each rule is tested on its own. The hub is never given a path the browser chose.
public enum JoinShareRules {
    public static let maxBodyBytes = 16 * 1024
    public static let timeoutSeconds: TimeInterval = 10
    public static let maxReplyBytes = 256 * 1024
    public static let maxNameCharacters = 64
    public static let panelPrefix = ["", "api", "join-share"]

    /// Letters, digits, `.`, `-`, `_`, at most 64. `.` and `..` are refused too: they would walk out of the hub path.
    public static func isValidName(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.count <= maxNameCharacters, text != ".", text != ".." else { return false }
        return text.unicodeScalars.allSatisfy(nameCharacters.contains)
    }

    private static let nameCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")

    /// The allow-list. `nil` is a plain 404: another method, another path, a trailing slash, or an id or name that is not valid.
    public static func match(method: String, path: String) -> JoinShareMatch? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > panelPrefix.count, Array(parts.prefix(panelPrefix.count)) == panelPrefix else { return nil }
        let rest = Array(parts.dropFirst(panelPrefix.count))
        switch (method, rest.count) {
        case ("GET", 1): return simple(method, rest[0])
        case ("POST", 1) where rest[0] == "links":
            return .hub(JoinShareCall(method: method, hubPath: "/admin/links", auditAction: "join_share.link"))
        case ("POST", 3) where rest[0] == "pending": return pendingAction(rest)
        case ("DELETE", 2) where rest[0] == "peers" && isValidName(rest[1]):
            return .hub(JoinShareCall(method: method, hubPath: "/admin/peers/\(rest[1])", auditAction: "join_share.remove", auditTarget: rest[1]))
        default: return nil
        }
    }

    private static func simple(_ method: String, _ name: String) -> JoinShareMatch? {
        switch name {
        case "status": return .status
        case "supported", "pending", "peers": return .hub(JoinShareCall(method: method, hubPath: "/admin/\(name)"))
        default: return nil
        }
    }

    private static func pendingAction(_ rest: [String]) -> JoinShareMatch? {
        let id = rest[1]
        guard isValidName(id), ["approve", "refuse"].contains(rest[2]) else { return nil }
        return .hub(JoinShareCall(method: "POST", hubPath: "/admin/pending/\(id)/\(rest[2])", auditAction: "join_share.\(rest[2])", auditTarget: id))
    }

    /// The audit target of a new link: `os/cpu` from the request body, or `link` when the body does not say (the hub then refuses it).
    /// Only the two words are read; nothing else of the body is kept.
    public static func linkTarget(body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let os = object["os"] as? String, let cpu = object["cpu"] as? String,
              isValidName(os), isValidName(cpu) else { return "link" }
        return "\(os)/\(cpu)"
    }

    /// A request body is forwarded only when it is one JSON object (or empty), so the hub never gets anything else.
    public static func isForwardableBody(_ body: Data) -> Bool {
        guard !body.isEmpty else { return true }
        return body.count <= maxBodyBytes && (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) != nil
    }

    /// The hub's admin address: http or https, a host, no login in it, no path, no query. Plain http is only for this machine, because the admin key travels in the request.
    public static func isAcceptableAdminURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, ["", "/"].contains(url.path) else { return false }
        return scheme == "https" || loopbackHosts.contains(host)
    }

    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    /// The key as the hub's `admin.key` file holds it: the text without the end-of-line. Empty means there is no key.
    public static func adminKey(fileText: String) -> String? {
        let key = fileText.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// A hub reply is passed on only when it is JSON (or empty) and does not hold the key. Anything else is "the hub is not answering properly".
    public static func isPassableReply(_ body: Data, key: String) -> Bool {
        guard body.count <= maxReplyBytes else { return false }
        if !body.isEmpty, (try? JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed)) == nil { return false }
        return !String(decoding: body, as: UTF8.self).contains(key)
    }
}
