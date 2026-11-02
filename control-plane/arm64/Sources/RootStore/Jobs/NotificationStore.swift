import Foundation
import RootCore

public struct NotificationRow: Encodable, Equatable {
    public let id: Int
    public let kind: String
    public let title: String
    public let detail: String
    public let commandId: String
    public let machine: String
    public let workloadId: String?
    public let createdAt: String
    public let readAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, detail, machine
        case commandId = "command_id"
        case workloadId = "workload_id"
        case createdAt = "created_at"
        case readAt = "read_at"
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(kind, forKey: .kind)
        try box.encode(title, forKey: .title)
        try box.encode(detail, forKey: .detail)
        try box.encode(commandId, forKey: .commandId)
        try box.encode(machine, forKey: .machine)
        try box.encode(workloadId, forKey: .workloadId)
        try box.encode(createdAt, forKey: .createdAt)
        try box.encode(readAt, forKey: .readAt)
    }
}

public struct NotificationPage: Equatable {
    public let rows: [NotificationRow]
    public let total: Int
    public let unreadCount: Int
}

/// What users are told when a long action ends. Every read and write names the user, so one user can never reach another's rows.
public struct NotificationStore {
    private let database: Database
    public static let retentionDays = 30
    public static let maxIdsPerMark = 100
    public static let maxPageSize = 100
    private static let secondsPerDay: TimeInterval = 86_400

    public init(_ database: Database) { self.database = database }

    /// One notification per job: a second call for the same job changes nothing. A job that is not final, or has no user, makes none.
    public func add(for command: CommandRow, now: Date) throws {
        let minutes = JobLimits.seconds(forType: command.type) / 60
        guard !command.actor.isEmpty, let notice = JobNotice.make(type: command.type, state: command.state, machine: command.machine, workload: command.workloadId, minutes: minutes) else { return }
        try database.execute("""
            INSERT OR IGNORE INTO notifications (user, kind, title, detail, command_id, machine_id, workload_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(command.actor), .text(notice.kind), .text(notice.title), .text(notice.detail), .text(command.id), .text(command.machine),
                  command.workloadId.map(SQLValue.text) ?? .null, .int(Int(now.timeIntervalSince1970))])
    }

    /// Newest first. `total` counts the rows the filter keeps; `unreadCount` counts every unread row of the user (the bell).
    public func page(user: String, page: Int, pageSize: Int, unreadOnly: Bool) throws -> NotificationPage {
        let size = min(max(pageSize, 1), Self.maxPageSize)
        let offset = (max(page, 1) - 1) * size
        let unread = try unreadCount(user: user)
        let rows = unreadOnly ? try unreadRows(user: user, size: size, offset: offset) : try allRows(user: user, size: size, offset: offset)
        let total = unreadOnly ? unread : try count(user: user)
        return NotificationPage(rows: rows, total: total, unreadCount: unread)
    }

    public func unreadCount(user: String) throws -> Int {
        try database.query("SELECT COUNT(*) AS n FROM notifications WHERE user = ? AND read_at IS NULL", [.text(user)]).first?.int("n") ?? 0
    }

    /// Marks these ids read for this user. Ids that are unknown, someone else's, or already read are skipped. Returns how many changed.
    public func markRead(user: String, ids: [Int], now: Date) throws -> Int {
        let stamp = SQLValue.int(Int(now.timeIntervalSince1970))
        return try database.transaction {
            try ids.prefix(Self.maxIdsPerMark).reduce(0) { changed, id in
                changed + (try database.execute("UPDATE notifications SET read_at = ? WHERE id = ? AND user = ? AND read_at IS NULL", [stamp, .int(id), .text(user)]))
            }
        }
    }

    public func markAllRead(user: String, now: Date) throws -> Int {
        try database.execute("UPDATE notifications SET read_at = ? WHERE user = ? AND read_at IS NULL", [.int(Int(now.timeIntervalSince1970)), .text(user)])
    }

    /// Deletes what is older than the retention. Returns how many.
    public func prune(now: Date) throws -> Int {
        let cutoff = now.addingTimeInterval(-TimeInterval(Self.retentionDays) * Self.secondsPerDay)
        return try database.execute("DELETE FROM notifications WHERE created_at < ?", [.int(Int(cutoff.timeIntervalSince1970))])
    }

    private func count(user: String) throws -> Int {
        try database.query("SELECT COUNT(*) AS n FROM notifications WHERE user = ?", [.text(user)]).first?.int("n") ?? 0
    }

    private func allRows(user: String, size: Int, offset: Int) throws -> [NotificationRow] {
        try database.query("""
            SELECT id, kind, title, detail, command_id, machine_id, workload_id, created_at, read_at FROM notifications WHERE user = ?
            ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?
            """, [.text(user), .int(size), .int(offset)]).map(row)
    }

    private func unreadRows(user: String, size: Int, offset: Int) throws -> [NotificationRow] {
        try database.query("""
            SELECT id, kind, title, detail, command_id, machine_id, workload_id, created_at, read_at FROM notifications WHERE user = ? AND read_at IS NULL
            ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?
            """, [.text(user), .int(size), .int(offset)]).map(row)
    }

    private func row(_ row: Row) -> NotificationRow {
        NotificationRow(id: row.int("id"), kind: row.string("kind"), title: row.string("title"), detail: row.string("detail"), commandId: row.string("command_id"),
                        machine: row.string("machine_id"), workloadId: row.optionalString("workload_id"), createdAt: Dates.iso(row.int("created_at")),
                        readAt: row.optionalInt("read_at").map(Dates.iso))
    }
}
