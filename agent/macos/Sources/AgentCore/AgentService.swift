import Foundation
import MSCore

public enum AgentError: Error, Equatable {
    case notFound
}

public struct Health: Encodable, Equatable {
    public let status = "ok"
    public let agentVersion: String
    public let contractVersion: String
    public let bundleVersion: String?

    enum CodingKeys: String, CodingKey { case status, agentVersion, contractVersion, bundleVersion }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(status, forKey: .status)
        try box.encode(agentVersion, forKey: .agentVersion)
        try box.encode(contractVersion, forKey: .contractVersion)
        try box.encode(bundleVersion, forKey: .bundleVersion)
    }
}

public enum Contract {
    /// The version of contract/openapi.yaml this Agent implements.
    public static let version = ContractVersion.current
}

/// Puts the chat bundle on this machine or inside a workload. The result carries the version, the port and the access key.
public protocol BundleInstalling: Sendable {
    func install(_ request: BundleInstallRequest) async throws -> [String: String]
    /// The version installed on this machine itself, if any.
    func installedVersion() async -> String?
}

/// Everything the Agent does, in one place, on top of an Engine. HTTP and the system probes live outside of it.
public actor AgentService {
    private let engine: Engine
    private var budget: SpaceBudget
    private let specs: MachineSpecs
    private let agentVersion: String
    private let osAvailableDiskGb: @Sendable () -> Int?
    private let ledger: CommandLedger
    private var inflight: [String: Workload] = [:]
    private var deleting: Set<String> = []
    private let installer: BundleInstalling?
    /// Called when something about the workloads changed, so the Root can hear about it without waiting for the next heartbeat.
    public nonisolated(unsafe) var onChange: (@Sendable () -> Void)?

    public init(engine: Engine, budget: SpaceBudget, specs: MachineSpecs, agentVersion: String, ledger: CommandLedger = CommandLedger(), installer: BundleInstalling? = nil,
                osAvailableDiskGb: @escaping @Sendable () -> Int? = { nil }) {
        self.installer = installer
        self.engine = engine
        self.budget = budget
        self.specs = specs
        self.agentVersion = agentVersion
        self.ledger = ledger
        self.osAvailableDiskGb = osAvailableDiskGb
    }

    // MARK: reading

    public func health() async -> Health {
        Health(agentVersion: agentVersion, contractVersion: Contract.version, bundleVersion: await installer?.installedVersion())
    }

    public func facts() async throws -> Facts {
        let all = try await workloads()
        return Facts(specs: specs, freeRamMb: budget.freeRamMb(workloads: all), freeDiskGb: budget.freeDiskGb(workloads: all), capabilities: engine.capabilities, problems: engine.problems)
    }

    public func workloads() async throws -> [Workload] {
        var byId = Dictionary(uniqueKeysWithValues: try await engine.list().map { ($0.id, $0) })
        for (id, planned) in inflight where byId[id] == nil { byId[id] = planned }
        for id in deleting { byId[id]?.state = .deleting }
        return byId.values.sorted { $0.name < $1.name }
    }

    public func command(_ id: String) throws -> Command {
        guard let found = ledger.find(id) else { throw AgentError.notFound }
        return found
    }

    // MARK: commands

    /// Checks the space, reserves it, and creates the workload in the background. A repeat of the same command id changes nothing.
    public func create(_ request: CreateWorkloadRequest) async throws -> Command {
        if let existing = ledger.find(request.commandId) { return existing }
        let current = try await workloads()
        try budget.check(request, workloads: current, capabilities: engine.capabilities, osAvailableDiskGb: osAvailableDiskGb())
        let id = "w-" + Tokens.random(bytes: 5).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(8)
        let planned = Workload(id: id, name: request.name, kind: request.kind, state: .provisioning, cpu: request.cpu, ramMb: request.ramMb,
                               diskGb: request.diskGb, gpuMode: request.gpuMode)
        inflight[id] = planned
        let command = Command(commandId: request.commandId, type: .create, state: .running, workloadId: id)
        ledger.record(command)
        Task { await self.finishCreate(command, id: id, request: request) }
        return command
    }

    private func finishCreate(_ started: Command, id: String, request: CreateWorkloadRequest) async {
        var done = started
        do {
            _ = try await engine.create(id: id, request: request)
            done.state = .succeeded
            done.result = ["workload_id": id]
        } catch {
            done.state = .failed
            done.result = ["error": "the machine could not create the workload"]
        }
        inflight[id] = nil
        ledger.record(done)
        onChange?()
    }

    public func start(commandId: String, id: String) async throws -> Command { try await setRunning(commandId, id, .start, running: true) }

    public func stop(commandId: String, id: String) async throws -> Command { try await setRunning(commandId, id, .stop, running: false) }

    private func setRunning(_ commandId: String, _ id: String, _ type: CommandType, running: Bool) async throws -> Command {
        if let existing = ledger.find(commandId) { return existing }
        guard try await workloads().contains(where: { $0.id == id }) else { throw AgentError.notFound }
        var command = Command(commandId: commandId, type: type, state: .running, workloadId: id)
        do {
            try await engine.setRunning(id: id, running: running)
            command.state = .succeeded
            command.result = ["state": running ? "running" : "stopped"]
        } catch {
            command.state = .failed
            command.result = ["error": "the machine could not change the workload"]
        }
        ledger.record(command)
        onChange?()
        return command
    }

    /// Backs up the disk first, then deletes. The backup name is part of the result.
    public func delete(commandId: String, id: String) async throws -> Command {
        if let existing = ledger.find(commandId) { return existing }
        guard try await workloads().contains(where: { $0.id == id }) else { throw AgentError.notFound }
        deleting.insert(id)
        let command = Command(commandId: commandId, type: .delete, state: .running, workloadId: id)
        ledger.record(command)
        Task { await self.finishDelete(command, id: id) }
        return command
    }

    private func finishDelete(_ started: Command, id: String) async {
        var done = started
        do {
            let backup = try await engine.backup(id: id)
            try await engine.delete(id: id)
            done.state = .succeeded
            done.result = ["backup_id": backup]
        } catch {
            done.state = .failed
            done.result = ["error": "the machine could not delete the workload"]
        }
        deleting.remove(id)
        ledger.record(done)
        onChange?()
    }

    /// Installs the bundle in the background. A repeat of the same command id changes nothing.
    public func installBundle(_ request: BundleInstallRequest) async throws -> Command {
        if let existing = ledger.find(request.commandId) { return existing }
        if let target = request.workloadId {
            guard try await workloads().contains(where: { $0.id == target && $0.state == .running }) else { throw AgentError.notFound }
        }
        let command = Command(commandId: request.commandId, type: .bundleInstall, state: .running, workloadId: request.workloadId)
        ledger.record(command)
        Task { await self.finishInstall(command, request) }
        return command
    }

    private func finishInstall(_ started: Command, _ request: BundleInstallRequest) async {
        var done = started
        do {
            guard let installer else { throw EngineError.failed("this Agent has no bundle installer") }
            done.result = try await installer.install(request)
            done.state = .succeeded
        } catch {
            done.state = .failed
            done.result = ["error": "the bundle could not be installed"]
        }
        ledger.record(done)
        onChange?()
    }
}
