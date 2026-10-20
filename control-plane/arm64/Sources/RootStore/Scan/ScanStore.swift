import Foundation
import RootCore

public struct ScanResultRow: Encodable, Equatable {
    public let id: Int
    public let ip: String
    public let mac: String?
    public let hostname: String?
    public let vendor: String?
    public let seenBy: [String]
    public let agentPortOpen: Bool
    /// Name of the enrolled machine at this address, if there is one.
    public let machine: String?

    enum CodingKeys: String, CodingKey { case id, ip, mac, hostname, vendor, seenBy, agentPortOpen, machine }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(ip, forKey: .ip)
        try box.encode(mac, forKey: .mac)
        try box.encode(hostname, forKey: .hostname)
        try box.encode(vendor, forKey: .vendor)
        try box.encode(seenBy, forKey: .seenBy)
        try box.encode(agentPortOpen, forKey: .agentPortOpen)
        try box.encode(machine, forKey: .machine)
    }
}

public struct ScanRunSummary: Encodable, Equatable {
    public let id: Int
    public let state: String
    public let subnet: String
    public let sources: [String: String]
    public let startedAt: String
    public let finishedAt: String?
    public let results: [ScanResultRow]

    enum CodingKeys: String, CodingKey { case id, state, subnet, sources, startedAt, finishedAt, results }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(state, forKey: .state)
        try box.encode(subnet, forKey: .subnet)
        try box.encode(sources, forKey: .sources)
        try box.encode(startedAt, forKey: .startedAt)
        try box.encode(finishedAt, forKey: .finishedAt)
        try box.encode(results, forKey: .results)
    }
}

public enum ScanError: Error, Equatable {
    case alreadyRunning
    case notFound
}

/// The latest scan, kept in memory only. A scan is a look at the network right now, so nothing about it is written to the database: opening
/// Find machines always runs a fresh one, and a new run replaces the old. The database is read only to mark devices that are already machines.
public final class ScanStore: @unchecked Sendable {
    private struct Run {
        let id: Int
        let subnet: String
        let startedAt: Date
        var state = "running"
        var sources: [String: String] = [:]
        var finishedAt: Date?
        var findings: [ScanFinding] = []
    }

    public static let staleAfter: TimeInterval = 15 * 60

    private let database: Database
    private let lock = NSLock()
    private var current: Run?
    private var lastId = 0

    public init(_ database: Database) { self.database = database }

    /// Begins a run, or refuses if one is already going. A run that never finished (a crash) stops counting after a while.
    public func start(subnet: String, now: Date) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let run = current, run.state == "running", now.timeIntervalSince(run.startedAt) < Self.staleAfter { throw ScanError.alreadyRunning }
        lastId += 1
        current = Run(id: lastId, subnet: subnet, startedAt: now)
        return lastId
    }

    public func finish(runId: Int, findings: [ScanFinding], sources: [String: String], now: Date) {
        update(runId) { run in
            run.state = "done"
            run.findings = findings
            run.sources = sources
            run.finishedAt = now
        }
    }

    public func fail(runId: Int, sources: [String: String], now: Date) {
        update(runId) { run in
            run.state = "failed"
            run.sources = sources
            run.finishedAt = now
        }
    }

    public func latest() throws -> ScanRunSummary? {
        lock.lock()
        let run = current
        lock.unlock()
        return try run.map(summary)
    }

    public func get(id: Int) throws -> ScanRunSummary {
        lock.lock()
        let run = current
        lock.unlock()
        guard let run, run.id == id else { throw ScanError.notFound }
        return try summary(run)
    }

    /// One result of one run, for the add step.
    public func result(runId: Int, resultId: Int) throws -> ScanResultRow {
        guard let row = try get(id: runId).results.first(where: { $0.id == resultId }) else { throw ScanError.notFound }
        return row
    }

    /// A run that a newer run has replaced is ignored: its late answer must not overwrite the new one.
    private func update(_ runId: Int, _ change: (inout Run) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard var run = current, run.id == runId else { return }
        change(&run)
        current = run
    }

    private func summary(_ run: Run) throws -> ScanRunSummary {
        let sorted = run.findings.sorted { (Subnet.address($0.ip) ?? 0) < (Subnet.address($1.ip) ?? 0) }
        let rows = try sorted.enumerated().map { index, item in
            ScanResultRow(id: index + 1, ip: item.ip, mac: item.mac, hostname: item.hostname, vendor: item.vendor, seenBy: item.seenBy.map(\.rawValue),
                          agentPortOpen: item.agentPortOpen, machine: try machineName(at: item.ip))
        }
        return ScanRunSummary(id: run.id, state: run.state, subnet: run.subnet, sources: run.sources, startedAt: Dates.iso(Int(run.startedAt.timeIntervalSince1970)),
                              finishedAt: run.finishedAt.map { Dates.iso(Int($0.timeIntervalSince1970)) }, results: rows)
    }

    private func machineName(at ip: String) throws -> String? {
        try database.query("SELECT name FROM machines WHERE ip = ? LIMIT 1", [.text(ip)]).first?.optionalString("name")
    }
}
