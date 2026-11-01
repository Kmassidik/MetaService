import Foundation
import RootCore

/// The event log: the single rows (logins, blocks, unblocks) and the failed-login day counts, together, newest first.
extension SecurityStore {
    private static let likeEscape: Character = "!"
    private static let failedType = SecurityEventType.failedLogin.rawValue

    public func eventsPage(_ query: SecurityQuery, now: Date) throws -> SecurityEventsReply {
        let filter = Filter(query, now: now)
        let total = try database.query("""
            SELECT COUNT(*) AS total FROM (
              SELECT 1 FROM events WHERE time >= ? AND (? = '' OR machine = ?) AND (? = '' OR type = ?)
                AND (? = '' OR user LIKE ? ESCAPE '!' OR address LIKE ? ESCAPE '!')
              UNION ALL
              SELECT 1 FROM failed_slots WHERE kind = ? AND slot >= ? AND (? = '' OR machine = ?) AND (? = '' OR ? = 'failed_login')
                AND (? = '' OR user LIKE ? ESCAPE '!' OR address LIKE ? ESCAPE '!')
            )
            """, filter.values).first?.int("total") ?? 0
        let rows = try database.query("""
            SELECT * FROM (
              SELECT 'e' || id AS id, time, machine, type, user, address, detail, method, count FROM events WHERE time >= ? AND (? = '' OR machine = ?) AND (? = '' OR type = ?)
                AND (? = '' OR user LIKE ? ESCAPE '!' OR address LIKE ? ESCAPE '!')
              UNION ALL
              SELECT id, last_seen AS time, machine, 'failed_login' AS type, NULLIF(user, '') AS user, NULLIF(address, '') AS address, NULL AS detail, NULL AS method, count
                FROM failed_slots WHERE kind = ? AND slot >= ? AND (? = '' OR machine = ?) AND (? = '' OR ? = 'failed_login')
                AND (? = '' OR user LIKE ? ESCAPE '!' OR address LIKE ? ESCAPE '!')
            ) ORDER BY time DESC, id DESC LIMIT ? OFFSET ?
            """, filter.values + [.int(query.pageSize), .int(query.offset)])
        return SecurityEventsReply(events: rows.map(eventRow), total: total, page: query.page, pageSize: query.pageSize)
    }

    private func eventRow(_ row: Row) -> SecurityEventRow {
        let type = row.string("type")
        return SecurityEventRow(id: row.string("id"), time: row.string("time"), machine: row.string("machine"), type: type, user: row.optionalString("user"),
                                address: row.optionalString("address"), detail: row.optionalString("detail"), method: row.optionalString("method"),
                                count: type == Self.failedType ? row.optionalInt("count") : nil)
    }

    /// The bound values of both halves of the query, in the order the `?` marks appear.
    private struct Filter {
        let values: [SQLValue]

        init(_ query: SecurityQuery, now: Date) {
            let start = SQLValue.text(SecurityTime.text(query.range.start(now: now)))
            let window = query.range.window(now: now).bound
            let machine = SQLValue.text(query.machine)
            let type = SQLValue.text(query.type?.rawValue ?? "")
            let like = query.text.isEmpty ? SQLValue.text("") : SQLValue.text("%" + SecurityStore.escaped(query.text) + "%")
            let asked = SQLValue.text(query.text)
            let single: [SQLValue] = [start, machine, machine, type, type, asked, like, like]
            let daily: [SQLValue] = window + [machine, machine, type, type, asked, like, like]
            values = single + daily
        }
    }

    /// `%`, `_` and the escape mark itself are plain characters in a search.
    static func escaped(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if "%_!".contains(character) { result.append(likeEscape) }
            result.append(character)
        }
    }
}
