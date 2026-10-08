import Foundation
import AgentCore
import MSCore

/// The Apple `container` program. One call is one program run with an argument list; there is no shell.
protocol ContainerCLI: Sendable {
    func run(_ arguments: [String], timeout: TimeInterval) async throws -> Data
}

struct ProcessContainerCLI: ContainerCLI {
    let path: String

    static let searchPaths = ["/usr/local/bin/container", "/opt/homebrew/bin/container", "/usr/bin/container"]

    static func locate(_ configured: String?) -> String? {
        ([configured].compactMap { $0 } + (configured == nil ? searchPaths : [])).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func run(_ arguments: [String], timeout: TimeInterval) async throws -> Data {
        do {
            return try await CommandRunner.run(path, arguments, timeout: timeout)
        } catch CommandFailure.failed(let status, let errors) {
            throw EngineError.failed("container \(arguments.first ?? "") exited with \(status): \(errors.suffix(300))")
        } catch CommandFailure.timedOut {
            throw EngineError.failed("container \(arguments.first ?? "") took too long")
        } catch {
            throw EngineError.failed("container \(arguments.first ?? "") could not run")
        }
    }
}

/// What the Agent remembers about its workloads, in one small file (mode 600), written whole and swapped in.
final class RecordStore: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private var records: [String: WorkloadRecord]

    init(path: String) {
        self.path = path
        records = (FileManager.default.contents(atPath: path).flatMap { try? JSONDecoder().decode([String: WorkloadRecord].self, from: $0) }) ?? [:]
    }

    func all() -> [String: WorkloadRecord] {
        lock.lock(); defer { lock.unlock() }
        return records
    }

    func set(_ id: String, _ record: WorkloadRecord) throws {
        lock.lock(); defer { lock.unlock() }
        records[id] = record
        try save()
    }

    func remove(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        records[id] = nil
        try save()
    }

    private func save() throws {
        let data = try JSONEncoder().encode(records)
        let temporary = path + ".tmp"
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]) else { throw EngineError.failed("cannot save the workload list") }
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: temporary))
    }
}
