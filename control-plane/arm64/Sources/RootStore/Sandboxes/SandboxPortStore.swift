import Foundation
import RootCore

public enum SandboxPortStoreError: Error, Equatable {
    /// Two different ports of two sandboxes asked for the same label. Its 80 bits are derived, so this is a bug or a
    /// once-in-a-universe collision, never something a caller can provoke on purpose.
    case labelTaken
}

/// One exposed port: the label a program fetches and the (sandbox, port) behind it. Never a secret: the token that proves
/// the caller was given this host is not stored, and is made again from the Root's key when needed.
public struct SandboxPortRecord: Equatable {
    public let sandbox: String
    public let port: Int
    public let label: String
    public let createdAt: Date

    public init(sandbox: String, port: Int, label: String, createdAt: Date) {
        self.sandbox = sandbox
        self.port = port
        self.label = label
        self.createdAt = createdAt
    }
}

/// The public ports of the sandboxes: what a label stands for (see `sandbox/README.md`, "Addresses"). One topic: the
/// `sandbox_ports` table. A removed sandbox's rows go with it (the foreign key).
public struct SandboxPortStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    /// Finds or makes the row for (sandbox, port), and says which it was. A second expose of the same port answers the row
    /// that is already there, with the label it was given then, so a program that asks twice gets the same host both times.
    @discardableResult
    public func expose(sandbox: String, port: Int, label: String, now: Date) throws -> (record: SandboxPortRecord, created: Bool) {
        try database.transaction {
            if let existing = try find(sandbox: sandbox, port: port) { return (existing, false) }
            if try find(label: label) != nil { throw SandboxPortStoreError.labelTaken }
            try database.execute("INSERT INTO sandbox_ports (sandbox, port, label, created_at) VALUES (?, ?, ?, ?)",
                                 [.text(sandbox), .int(port), .text(label), .int(Int(now.timeIntervalSince1970))])
            return (SandboxPortRecord(sandbox: sandbox, port: port, label: label, createdAt: now), true)
        }
    }

    /// The port one label stands for, or nil when no row has it: an unknown label is a closed door, the same as a port
    /// nothing listens on.
    public func find(label: String) throws -> SandboxPortRecord? {
        try database.query("SELECT sandbox, port, label, created_at FROM sandbox_ports WHERE label = ?", [.text(label)])
            .first.map(Self.record)
    }

    public func find(sandbox: String, port: Int) throws -> SandboxPortRecord? {
        try database.query("SELECT sandbox, port, label, created_at FROM sandbox_ports WHERE sandbox = ? AND port = ?",
                           [.text(sandbox), .int(port)]).first.map(Self.record)
    }

    /// Every port one sandbox has exposed, oldest first.
    public func list(sandbox: String) throws -> [SandboxPortRecord] {
        try database.query("SELECT sandbox, port, label, created_at FROM sandbox_ports WHERE sandbox = ? ORDER BY created_at, port",
                           [.text(sandbox)]).map(Self.record)
    }

    private static func record(_ row: Row) -> SandboxPortRecord {
        SandboxPortRecord(sandbox: row.string("sandbox"), port: row.int("port"), label: row.string("label"),
                          createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))))
    }
}
