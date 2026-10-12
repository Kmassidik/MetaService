import Foundation

/// What the parent remembers about a machine it installed over SSH: where it is, which host key it trusts, where its box is, and what the install added, so it can be removed exactly.
public struct RemoteMachine: Equatable {
    public let machine: String
    public let host: String
    public let sshPort: Int
    public let sshUser: String
    public let fingerprint: String
    public let level: String
    public let box: String
    public let sshDirectory: String
    public let agentPort: Int
    public let engine: String
    public let keyName: String?
    public let keyFile: String?
    public let keyMarker: String?
    public let keyFileCreated: Bool
    public let sshDirCreated: Bool

    public init(machine: String, host: String, sshPort: Int, sshUser: String, fingerprint: String, level: String, box: String, sshDirectory: String, agentPort: Int, engine: String,
                keyName: String?, keyFile: String?, keyMarker: String?, keyFileCreated: Bool, sshDirCreated: Bool) {
        self.machine = machine
        self.host = host
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.fingerprint = fingerprint
        self.level = level
        self.box = box
        self.sshDirectory = sshDirectory
        self.agentPort = agentPort
        self.engine = engine
        self.keyName = keyName
        self.keyFile = keyFile
        self.keyMarker = keyMarker
        self.keyFileCreated = keyFileCreated
        self.sshDirCreated = sshDirCreated
    }
}

public struct RemoteMachineStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    public func save(_ record: RemoteMachine, now: Date) throws {
        try database.execute("""
            INSERT OR REPLACE INTO remote_machines (machine, host, ssh_port, ssh_user, fingerprint, level, box, ssh_dir, agent_port, engine, key_name, key_file, key_marker, key_file_created, ssh_dir_created, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(record.machine), .text(record.host), .int(record.sshPort), .text(record.sshUser), .text(record.fingerprint), .text(record.level), .text(record.box), .text(record.sshDirectory),
                  .int(record.agentPort), .text(record.engine), record.keyName.map(SQLValue.text) ?? .null, record.keyFile.map(SQLValue.text) ?? .null, record.keyMarker.map(SQLValue.text) ?? .null,
                  .int(record.keyFileCreated ? 1 : 0), .int(record.sshDirCreated ? 1 : 0), .int(Int(now.timeIntervalSince1970))])
    }

    public func get(_ machine: String) throws -> RemoteMachine? {
        try database.query("SELECT * FROM remote_machines WHERE machine = ?", [.text(machine)]).first.map(Self.read)
    }

    public func all() throws -> [RemoteMachine] {
        try database.query("SELECT * FROM remote_machines ORDER BY machine").map(Self.read)
    }

    public func remove(_ machine: String) throws {
        try database.execute("DELETE FROM remote_machines WHERE machine = ?", [.text(machine)])
    }

    private static func read(_ row: Row) -> RemoteMachine {
        RemoteMachine(machine: row.string("machine"), host: row.string("host"), sshPort: row.int("ssh_port"), sshUser: row.string("ssh_user"), fingerprint: row.string("fingerprint"),
                      level: row.string("level"), box: row.string("box"), sshDirectory: row.string("ssh_dir"), agentPort: row.int("agent_port"), engine: row.string("engine"),
                      keyName: row.optionalString("key_name"), keyFile: row.optionalString("key_file"), keyMarker: row.optionalString("key_marker"),
                      keyFileCreated: row.int("key_file_created") == 1, sshDirCreated: row.int("ssh_dir_created") == 1)
    }
}
