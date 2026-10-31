import Foundation
import RootCore

/// A person who uses AI clients: a name, scopes and quotas. Not a login: the panel has one login, and a person only has tokens.
public struct McpPersonRecord: Equatable {
    public let id: String
    public let name: String
    public let scopes: Set<McpScope>
    public let quotas: McpQuotas
    public let createdAt: Date
    public let disabledAt: Date?

    public var isDisabled: Bool { disabledAt != nil }

    /// The actor name every audit row and command of this person's tokens carries.
    public var actor: String { "mcp:\(name)" }
}

public enum McpPeopleError: Error, Equatable {
    case nameTaken
    case notFound
}

/// The people (mcp/SPEC.md section 10.1). Quotas and the VMs belong to the person, however many tokens they have.
public struct McpPeopleStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    /// Names are unique ignoring case ("Ayu" and "ayu" are one person), which the column's own UNIQUE does not know.
    public func create(id: String, name: String, scopes: Set<McpScope>, quotas: McpQuotas, now: Date) throws {
        guard try find(name: name) == nil else { throw McpPeopleError.nameTaken }
        do {
            try database.execute("INSERT INTO mcp_people (id, name, scopes_json, quotas_json, created_at) VALUES (?, ?, ?, ?, ?)",
                                 [.text(id), .text(name), .text(Self.json(McpScope.names(scopes))), .text(Self.json(quotas.json)), .int(McpTokenStore.seconds(now))])
        } catch let error as DatabaseError where error.isConstraint {
            throw McpPeopleError.nameTaken
        }
    }

    public func get(id: String) throws -> McpPersonRecord? {
        try database.query("SELECT id, name, scopes_json, quotas_json, created_at, disabled_at FROM mcp_people WHERE id = ?", [.text(id)]).first.map(Self.record)
    }

    /// By name, ignoring case, so "ayu" and "Ayu" are one person.
    public func find(name: String) throws -> McpPersonRecord? {
        try database.query("SELECT id, name, scopes_json, quotas_json, created_at, disabled_at FROM mcp_people WHERE name = ? COLLATE NOCASE", [.text(name)]).first.map(Self.record)
    }

    public func list() throws -> [McpPersonRecord] {
        try database.query("SELECT id, name, scopes_json, quotas_json, created_at, disabled_at FROM mcp_people ORDER BY name COLLATE NOCASE").map(Self.record)
    }

    /// Changes what is named. A token's own scopes are not touched: its effective scopes are the overlap with the person's.
    public func change(id: String, scopes: Set<McpScope>?, quotas: McpQuotas?) throws {
        guard let current = try get(id: id) else { throw McpPeopleError.notFound }
        try database.execute("UPDATE mcp_people SET scopes_json = ?, quotas_json = ? WHERE id = ?",
                             [.text(Self.json(McpScope.names(scopes ?? current.scopes))), .text(Self.json((quotas ?? current.quotas).json)), .text(id)])
    }

    /// Disabling stops every token of the person at once; the VMs stay and keep their creator record. True when the state changed.
    @discardableResult
    public func setDisabled(id: String, _ disabled: Bool, now: Date) throws -> Bool {
        if disabled {
            return try database.execute("UPDATE mcp_people SET disabled_at = ? WHERE id = ? AND disabled_at IS NULL", [.int(McpTokenStore.seconds(now)), .text(id)]) > 0
        }
        return try database.execute("UPDATE mcp_people SET disabled_at = NULL WHERE id = ? AND disabled_at IS NOT NULL", [.text(id)]) > 0
    }

    private static func json(_ value: Any) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }

    private static func record(_ row: Row) -> McpPersonRecord {
        let names = (try? JSONSerialization.jsonObject(with: Data(row.string("scopes_json").utf8))) as? [String] ?? []
        return McpPersonRecord(id: row.string("id"), name: row.string("name"), scopes: Set(names.compactMap(McpScope.init(rawValue:))), quotas: McpQuotas(stored: row.string("quotas_json")),
                               createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))), disabledAt: row.optionalInt("disabled_at").map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }
}
