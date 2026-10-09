import Foundation

public struct BrainGrant: Equatable {
    public let machine: String
    public let workload: String?
}

public struct BrainUsage: Encodable, Equatable {
    public let machine: String
    public let workload: String?
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int
}

/// Short-lived capabilities for the AI proxy (only their hashes are kept) and what each machine and workload has used.
public struct BrainStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    public func issue(tokenHash: String, machine: String, workload: String?, expiresAt: Date, now: Date) throws {
        try database.execute("DELETE FROM brain_capabilities WHERE expires_at <= ?", [.int(Int(now.timeIntervalSince1970))])
        try database.execute("INSERT INTO brain_capabilities (token_hash, machine, workload, expires_at) VALUES (?, ?, ?, ?)",
                             [.text(tokenHash), .text(machine), workload.map { .text($0) } ?? .null, .int(Int(expiresAt.timeIntervalSince1970))])
    }

    /// Whose capability this is, or nil if it is unknown or has expired.
    public func lookup(tokenHash: String, now: Date) throws -> BrainGrant? {
        try database.query("SELECT machine, workload FROM brain_capabilities WHERE token_hash = ? AND expires_at > ?",
                           [.text(tokenHash), .int(Int(now.timeIntervalSince1970))]).first.map { BrainGrant(machine: $0.string("machine"), workload: $0.optionalString("workload")) }
    }

    public func record(machine: String, workload: String?, promptTokens: Int, completionTokens: Int, now: Date) throws {
        try database.execute("""
            INSERT INTO brain_usage (machine, workload, requests, prompt_tokens, completion_tokens, updated_at) VALUES (?, ?, 1, ?, ?, ?)
            ON CONFLICT (machine, workload) DO UPDATE SET requests = requests + 1, prompt_tokens = prompt_tokens + excluded.prompt_tokens,
              completion_tokens = completion_tokens + excluded.completion_tokens, updated_at = excluded.updated_at
            """, [.text(machine), .text(workload ?? ""), .int(promptTokens), .int(completionTokens), .int(Int(now.timeIntervalSince1970))])
    }

    public func usage() throws -> [BrainUsage] {
        try database.query("SELECT machine, workload, requests, prompt_tokens, completion_tokens FROM brain_usage ORDER BY machine, workload").map {
            BrainUsage(machine: $0.string("machine"), workload: $0.string("workload").isEmpty ? nil : $0.string("workload"),
                       requests: $0.int("requests"), promptTokens: $0.int("prompt_tokens"), completionTokens: $0.int("completion_tokens"))
        }
    }
}
