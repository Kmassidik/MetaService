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
    /// Turns the chat off on this machine or in a workload. It stops; its conversations stay where they are.
    func uninstall(workloadId: String?) async throws
    /// The version installed on this machine itself, if any.
    func installedVersion() async -> String?
}

/// Everything the Agent does, in one place, on top of an Engine. HTTP and the system probes live outside of it.
public actor AgentService {
    let engine: Engine
    private var budget: SpaceBudget
    private let specs: MachineSpecs
    private let readMachine: @Sendable () -> MachineReading?
    private let agentVersion: String
    private let agentBuild: String?
    private let ledger: CommandLedger
    private var inflight: [String: Workload] = [:]
    private var deleting: [String: Command] = [:]
    private static let maxDeleteErrorBytes = 300
    private let installer: BundleInstalling?
    /// The open consoles; stopping or deleting a workload ends its console.
    public nonisolated let consoles: ConsoleRegistry
    /// Called when something about the workloads changed, so the Root can hear about it without waiting for the next heartbeat.
    public nonisolated(unsafe) var onChange: (@Sendable () -> Void)?

    public init(engine: Engine, budget: SpaceBudget, specs: MachineSpecs, agentVersion: String, agentBuild: String? = nil, ledger: CommandLedger = CommandLedger(), installer: BundleInstalling? = nil,
                consoles: ConsoleRegistry = ConsoleRegistry(), readMachine: @escaping @Sendable () -> MachineReading? = { nil }) {
        self.consoles = consoles
        self.installer = installer
        self.engine = engine
        self.budget = budget
        self.specs = specs
        self.agentVersion = agentVersion
        self.agentBuild = agentBuild
        self.ledger = ledger
        self.readMachine = readMachine
    }

    /// Reads the machine's totals again and updates the budget in place; used before every facts report and every create.
    @discardableResult
    private func refreshBudget() -> MachineReading? {
        let reading = readMachine().flatMap(\.ifUsable)
        budget = budget.after(reading)
        return reading
    }

    // MARK: reading

    public func health() async -> Health {
        Health(agentVersion: agentVersion, contractVersion: Contract.version, bundleVersion: await installer?.installedVersion())
    }

    public func facts() async throws -> Facts {
        let all = try await workloads()
        let engineInfo = EngineInfo(identity: await engine.identity(), ready: engine.problems.isEmpty)
        refreshBudget()
        let fresh = specs.withTotals(ramTotalMb: budget.ramTotalMb, diskTotalGb: budget.diskTotalGb)
        return Facts(specs: fresh, freeRamMb: budget.freeRamMb(workloads: all), freeDiskGb: budget.freeDiskGb(workloads: all), capabilities: engine.capabilities,
                     problems: engine.problems, agentVersion: agentVersion, engine: engineInfo, agentBuild: agentBuild)
    }

    public func workloads() async throws -> [Workload] {
        var byId = Dictionary(uniqueKeysWithValues: try await engine.list().map { ($0.id, $0) })
        for (id, planned) in inflight where byId[id] == nil { byId[id] = planned }
        for (id, _) in deleting { byId[id]?.state = .deleting }
        return byId.values.sorted { $0.name < $1.name }
    }

    /// The program and arguments for a console in this workload (see `Engine.attach`).
    public func attach(id: String) async throws -> [String] {
        try await engine.attach(id: id)
    }

    /// Sets the complete list of SSH keys for root of one VM (see `Engine.applySshKeys`). The list is checked again here, whoever calls.
    /// With `installSshd` the keys are written first, then the SSH server is installed and started; a failure there throws `SshdFailure` and the keys stay written.
    public func applySshKeys(id: String, keys: [String], installSshd: Bool = false) async throws -> SshKeysResult {
        try SshKeyLines.validate(keys)
        let written = try await engine.applySshKeys(id: id, keys: keys)
        guard installSshd else { return written }
        let report = try await engine.installSshd(id: id)
        if let failure = report.failure { throw failure }
        return SshKeysResult(applied: written.applied, sshd: report.sshd, installed: report.installed)
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
        let reading = refreshBudget()
        try budget.check(request, workloads: current, capabilities: engine.capabilities, osAvailableDiskGb: reading?.diskAvailableGb)
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
        } catch EngineError.notReady(let why) {
            done.state = .failed
            done.result = ["error": why]
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
            if !running { consoles.end(id, .vmStopped) }
        } catch {
            command.state = .failed
            command.result = ["error": "the machine could not change the workload"]
        }
        ledger.record(command)
        onChange?()
        return command
    }

    /// Stops a running workload, backs up its disk, then deletes it. A failure restores the original running state when possible.
    public func delete(commandId: String, id: String) async throws -> Command {
        if let existing = ledger.find(commandId) { return existing }
        if let active = deleting[id] { return active }
        guard let workload = try await workloads().first(where: { $0.id == id }) else { throw AgentError.notFound }
        if let active = deleting[id] { return active }
        let command = Command(commandId: commandId, type: .delete, state: .running, workloadId: id)
        deleting[id] = command
        consoles.end(id, .vmDeleted)
        ledger.record(command)
        onChange?()
        Task { await self.finishDelete(command, id: id, wasRunning: workload.state == .running) }
        return command
    }

    private func finishDelete(_ started: Command, id: String, wasRunning: Bool) async {
        var done = started
        do {
            if wasRunning { try await engine.setRunning(id: id, running: false) }
            let backup = try await engine.backup(id: id)
            try await engine.delete(id: id)
            done.state = .succeeded
            done.result = ["backup_id": backup]
        } catch {
            done.state = .failed
            var reason = Self.deleteError(error)
            if wasRunning {
                do {
                    try await engine.setRunning(id: id, running: true)
                } catch {
                    reason += " (could not restart: \(Self.deleteError(error)))"
                }
            }
            done.result = ["error": Self.boundedDeleteError(reason)]
        }
        if deleting[id]?.commandId == started.commandId { deleting[id] = nil }
        ledger.record(done)
        onChange?()
    }

    private static func deleteError(_ error: Error) -> String {
        let reason: String
        switch error {
        case EngineError.notFound: reason = "the machine no longer has this workload"
        case EngineError.notRunning: reason = "the machine says this workload is not running"
        case EngineError.failed(let message), EngineError.notReady(let message): reason = message
        default: reason = String(describing: error)
        }
        return boundedDeleteError(reason)
    }

    private static func boundedDeleteError(_ reason: String) -> String {
        let line = reason.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        guard line.utf8.count > maxDeleteErrorBytes else { return line }
        var bounded = ""
        var byteCount = 0
        bounded.reserveCapacity(maxDeleteErrorBytes)
        for character in line {
            guard byteCount + character.utf8.count <= maxDeleteErrorBytes else { break }
            bounded.append(character)
            byteCount += character.utf8.count
        }
        return bounded
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

    /// Turns the chat off in the background. A repeat of the same command id changes nothing.
    public func uninstallBundle(_ request: BundleUninstallRequest) async throws -> Command {
        if let existing = ledger.find(request.commandId) { return existing }
        if let target = request.workloadId {
            guard try await workloads().contains(where: { $0.id == target && $0.state == .running }) else { throw AgentError.notFound }
        }
        let command = Command(commandId: request.commandId, type: .bundleUninstall, state: .running, workloadId: request.workloadId)
        ledger.record(command)
        Task { await self.finishUninstall(command, request) }
        return command
    }

    private func finishUninstall(_ started: Command, _ request: BundleUninstallRequest) async {
        var done = started
        do {
            guard let installer else { throw EngineError.failed("this Agent has no bundle installer") }
            try await installer.uninstall(workloadId: request.workloadId)
            done.state = .succeeded
            done.result = ["kept": "chat-data"]
        } catch {
            done.state = .failed
            done.result = ["error": "the chat could not be turned off"]
        }
        ledger.record(done)
        onChange?()
    }
}
