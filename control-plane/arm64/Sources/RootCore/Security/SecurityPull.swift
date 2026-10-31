import Foundation

public enum SecurityEventType: String, CaseIterable, Sendable {
    case failedLogin = "failed_login", login, blocked, unblocked
}

/// One event of a helper's answer, cleaned.
public struct SecurityHelperEvent: Equatable, Sendable {
    public let time: Date
    public let type: SecurityEventType
    public let user: String?
    public let address: String?
    public let method: String?
    /// For a failed login how many tries the event stands for; 1 for every other type.
    public let count: Int
    public let until: Date?
    public let detail: String?

    public init(time: Date, type: SecurityEventType, user: String?, address: String?, method: String?, count: Int, until: Date?, detail: String?) {
        self.time = time
        self.type = type
        self.user = user
        self.address = address
        self.method = method
        self.count = count
        self.until = until
        self.detail = detail
    }
}

public struct SecurityPullError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

/// A helper's answer to `GET /v1/security/events`, read and cleaned. Events that cannot be read are left out and counted in `dropped`.
public struct SecurityPull: Equatable, Sendable {
    public static let maxCursorLength = 256
    public static let maxCount = 1_000_000
    public static let methods = ["key", "password"]

    public let cursor: String
    /// The helper could not honour `after`: the events are a fresh start. Nothing stored is deleted.
    public let reset: Bool
    public let events: [SecurityHelperEvent]
    public let baseline: SecurityBaseline
    /// How many events the helper sent, readable or not; a full page means there may be more.
    public let received: Int
    public let dropped: Int

    public init(cursor: String, reset: Bool, events: [SecurityHelperEvent], baseline: SecurityBaseline, received: Int, dropped: Int) {
        self.cursor = cursor
        self.reset = reset
        self.events = events
        self.baseline = baseline
        self.received = received
        self.dropped = dropped
    }

    /// `limit` is the page size that was asked for: a helper that sends more breaks the contract.
    public static func parse(_ data: Data, limit: Int, now: Date) throws -> SecurityPull {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw SecurityPullError(description: "the answer is not a JSON object") }
        guard let cursor = body["cursor"] as? String, isUsable(cursor: cursor) else { throw SecurityPullError(description: "the cursor is missing or not usable") }
        guard let list = body["events"] as? [Any] else { throw SecurityPullError(description: "events is not a list") }
        guard list.count <= limit else { throw SecurityPullError(description: "the helper sent more events than asked for") }
        let events = list.compactMap { event($0, now: now) }
        return SecurityPull(cursor: cursor, reset: (body["reset"] as? Bool) ?? false, events: events, baseline: SecurityBaseline(helper: body["baseline"]),
                            received: list.count, dropped: list.count - events.count)
    }

    private static func isUsable(cursor: String) -> Bool {
        !cursor.isEmpty && cursor.count <= maxCursorLength && !cursor.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func event(_ value: Any, now: Date) -> SecurityHelperEvent? {
        guard let object = value as? [String: Any], let typeText = object["type"] as? String, let type = SecurityEventType(rawValue: typeText),
              let timeText = object["time"] as? String, let time = SecurityTime.normalized(timeText, now: now),
              let count = tries(object["count"], type: type) else { return nil }
        let until = type == .blocked ? (object["until"] as? String).flatMap(SecurityTime.parse) : nil
        let method = (object["method"] as? String).flatMap { methods.contains($0) ? $0 : nil }
        return SecurityHelperEvent(time: time, type: type, user: SecurityText.user(object["user"] as? String), address: SecurityText.address(object["address"] as? String),
                                   method: method, count: count, until: until, detail: SecurityText.detail(object["detail"] as? String))
    }

    /// A failed login stands for 1 or more tries (1 when the helper leaves it out); every other type is one event whatever the helper wrote.
    private static func tries(_ value: Any?, type: SecurityEventType) -> Int? {
        guard type == .failedLogin, let value else { return 1 }
        guard let number = value as? NSNumber, let whole = Int(exactly: number.doubleValue), (1...maxCount).contains(whole) else { return nil }
        return whole
    }
}
