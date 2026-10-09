import Foundation

public struct LocalAgentEntry: Equatable {
    public let machine: String
    public let binary: String
    public let arguments: [String]
    public let logPath: String
    public let port: Int

    public init(machine: String, binary: String, arguments: [String], logPath: String, port: Int) {
        self.machine = machine
        self.binary = binary
        self.arguments = arguments
        self.logPath = logPath
        self.port = port
    }
}

/// The Agents the control plane itself keeps running on its own computer, so a restart of the control plane starts them again.
public struct LocalAgentStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    public func save(_ entry: LocalAgentEntry) throws {
        let json = String(data: try JSONSerialization.data(withJSONObject: entry.arguments), encoding: .utf8) ?? "[]"
        try database.execute("INSERT OR REPLACE INTO local_agents (machine, binary, arguments_json, log_path, port) VALUES (?, ?, ?, ?, ?)",
                             [.text(entry.machine), .text(entry.binary), .text(json), .text(entry.logPath), .int(entry.port)])
    }

    public func all() throws -> [LocalAgentEntry] {
        try database.query("SELECT machine, binary, arguments_json, log_path, port FROM local_agents ORDER BY machine").map { row in
            let arguments = (try? JSONSerialization.jsonObject(with: Data(row.string("arguments_json").utf8)) as? [String]) ?? []
            return LocalAgentEntry(machine: row.string("machine"), binary: row.string("binary"), arguments: arguments, logPath: row.string("log_path"), port: row.int("port"))
        }
    }

    public func remove(machine: String) throws {
        try database.execute("DELETE FROM local_agents WHERE machine = ?", [.text(machine)])
    }
}
