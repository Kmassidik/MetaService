import Foundation
import RootCore
import RootStore

struct InstallJob: Encodable {
    let id: String
    let name: String
    var state: InstallState
    var steps: [InstallStep]
    var error: String?
    /// Set when the install worked but the machine says something stops it from creating VMs (for example a missing tool): the message and its fix.
    var warning: String?
}

/// Installs MetaService on the control plane's own computer, as the Add machine form asks: it invites the machine, starts its Agent, waits until the machine reports in
/// and, if asked, installs the chat. Each step is shown to the operator as it happens. One install runs at a time.
final class InstallService: @unchecked Sendable {
    private let services: Parts
    private let supervisor: LocalAgentSupervisor
    private let lock = NSLock()
    private var jobs: [String: InstallJob] = [:]
    private var active: String?

    private static let onlineSeconds = 60
    private static let chatSeconds = 90

    struct Parts {
        let config: RootConfig
        let clock: Clock
        let machines: MachineStore
        let enrollments: EnrollmentStore
        let audit: AuditStore
        let commands: CommandStore
        let bundles: BundleStore
        let workloads: WorkloadService
    }

    init(parts: Parts, supervisor: LocalAgentSupervisor) {
        services = parts
        self.supervisor = supervisor
    }

    func job(_ id: String) -> InstallJob? { lock.withLock { jobs[id] } }

    var agentReady: Bool { FileManager.default.isExecutableFile(atPath: services.config.agentBinary) }

    /// Checks what can be checked at once, then installs in the background. The answer is the job's id.
    func start(_ request: InstallRequest, actor: String) throws -> String {
        guard agentReady else {
            throw ApiFailure(status: .conflict, code: "agent_missing", message: "the MetaService program for this computer was not found: build it first (scripts/run-control-plane.sh does)")
        }
        guard (try? services.machines.get(id: request.name, now: services.clock.now)) == nil else {
            throw ApiFailure(status: .conflict, code: "machine_exists", message: "a machine with that name is already installed")
        }
        let id = "in-" + Tokens.random(bytes: 6).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(10)
        try lock.withLock {
            guard active == nil else { throw ApiFailure(status: .conflict, code: "install_running", message: "another install is still running") }
            active = id
            jobs[id] = InstallJob(id: id, name: request.name, state: .running, steps: InstallStep.plan(chat: request.chat), error: nil, warning: nil)
        }
        try services.audit.record(actor: actor, action: "machine.install", target: request.name, detail: ["chat": request.chat ? "yes" : "no"], at: services.clock.now)
        Task.detached { [self] in await run(id, request, actor: actor) }
        return id
    }

    private func run(_ id: String, _ request: InstallRequest, actor: String) async {
        do {
            try step(id, "check") { "The name and the program are fine." }
            try step(id, "agent") { try startAgent(request) }
            try await stepAsync(id, "online") { try await waitUntilOnline(request.name) }
            if request.chat { try await stepAsync(id, "chat") { try await installChat(request.name, actor: actor) } }
            finish(id, .done, error: nil, warning: warning(for: request.name))
        } catch {
            finish(id, .failed, error: (error as? InstallFailure)?.message ?? "something went wrong")
        }
    }

    // MARK: steps

    private func startAgent(_ request: InstallRequest) throws -> String {
        let core = services
        let stateDirectory = ((core.config.databasePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent("agents/" + request.name)
        try FileManager.default.createDirectory(atPath: stateDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let root = Self.rootAddress(core.config)
        let invite = try core.enrollments.create(machineName: request.name, expectedIp: root.host, now: core.clock.now)
        let tokenFile = stateDirectory + "/enroll.token"
        guard FileManager.default.createFile(atPath: tokenFile, contents: Data(invite.token.utf8), attributes: [.posixPermissions: 0o600]) else { throw InstallFailure("cannot write the invite file") }
        defer { try? FileManager.default.removeItem(atPath: tokenFile) }
        try Self.run(core.config.agentBinary, ["enroll", "--root", root.url, "--name", request.name, "--enrollment-token-file", tokenFile, "--state-dir", stateDirectory])
        var arguments = ["run", "--state-dir", stateDirectory, "--engine", "apple", "--port", String(core.config.localAgentPort), "--bind", "127.0.0.1",
                         "--chat-port", String(core.config.localChatPort), "--chat-bind", "127.0.0.1", "--heartbeat-seconds", "5"]
        if let ram = request.ramReserveMb { arguments += ["--ram-reserve-mb", String(ram)] }
        if let disk = request.diskReserveGb { arguments += ["--disk-reserve-gb", String(disk)] }
        try supervisor.start(LocalAgentEntry(machine: request.name, binary: core.config.agentBinary, arguments: arguments, logPath: stateDirectory + "/agent.log", port: core.config.localAgentPort))
        return "MetaService is running on this computer."
    }

    private func waitUntilOnline(_ name: String) async throws -> String {
        for _ in 0..<Self.onlineSeconds {
            if let machine = try? services.machines.get(id: name, now: services.clock.now), machine.state != "offline" { return "The machine reported in." }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw InstallFailure("the machine did not report in within \(Self.onlineSeconds) seconds; see its log in the agents folder")
    }

    private func installChat(_ name: String, actor: String) async throws -> String {
        let core = services
        if try core.bundles.pinned() == nil {
            guard let newest = try core.bundles.overview(now: core.clock.now).bundles.first?.version else { throw InstallFailure("there is no chat bundle on the control plane to install") }
            try core.bundles.pin(version: newest, actor: actor, now: core.clock.now)
        }
        let command = try await core.workloads.installBundle(actor: actor, machine: name, workload: nil)
        for _ in 0..<Self.chatSeconds {
            if let row = try core.commands.get(command.id), row.state == "succeeded" { return "The chat is installed." }
            if let row = try core.commands.get(command.id), row.state == "failed" { throw InstallFailure("the chat could not be installed: \(row.result?["error"] ?? "unknown reason")") }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw InstallFailure("the chat install did not finish in time")
    }

    // MARK: bookkeeping

    private func step(_ id: String, _ stepId: String, _ work: () throws -> String) throws {
        mark(id, stepId, .running, nil)
        do {
            mark(id, stepId, .done, try work())
        } catch {
            mark(id, stepId, .failed, (error as? InstallFailure)?.message)
            throw error
        }
    }

    private func stepAsync(_ id: String, _ stepId: String, _ work: () async throws -> String) async throws {
        mark(id, stepId, .running, nil)
        do {
            mark(id, stepId, .done, try await work())
        } catch {
            mark(id, stepId, .failed, (error as? InstallFailure)?.message)
            throw error
        }
    }

    private func mark(_ id: String, _ stepId: String, _ state: InstallState, _ detail: String?) {
        lock.withLock {
            guard var job = jobs[id], let index = job.steps.firstIndex(where: { $0.id == stepId }) else { return }
            job.steps[index].state = state
            job.steps[index].detail = detail
            jobs[id] = job
        }
    }

    private func warning(for name: String) -> String? {
        guard let problem = (try? services.machines.get(id: name, now: services.clock.now))?.problems.first else { return nil }
        return problem.message + " " + problem.fix
    }

    private func finish(_ id: String, _ state: InstallState, error: String?, warning: String? = nil) {
        lock.withLock {
            jobs[id]?.state = state
            jobs[id]?.error = error
            jobs[id]?.warning = warning
            active = nil
        }
    }

    private static func rootAddress(_ config: RootConfig) -> (url: String, host: String) {
        let host = config.agentListenBind == "0.0.0.0" ? "127.0.0.1" : config.agentListenBind
        return ("http://\(host):\(config.agentListenPort)", host)
    }

    /// Runs one program with a fixed argument list and fails with its last words if it does not succeed.
    private static func run(_ program: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallFailure("could not enroll: " + String(text.suffix(200)).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

struct InstallFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
