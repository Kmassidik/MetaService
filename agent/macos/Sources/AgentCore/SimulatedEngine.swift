import Foundation

/// An engine that only pretends. Used to test the Agent on a machine that has no virtualization tool, and by the conformance suite.
public actor SimulatedEngine: Engine {
    public nonisolated let capabilities: Capabilities
    private var store: [String: Workload] = [:]
    private var createFailure: EngineError?
    private var backupError: EngineError?
    private var backupDelayNanoseconds: UInt64 = 0
    private var deleteError: EngineError?
    private var restartError: EngineError?
    private var deleteDelayNanoseconds: UInt64 = 0
    /// Lifecycle calls in order, so tests can verify stop, backup, restart, and delete.
    public private(set) var lifecycleOperations: [String] = []
    /// What was pushed and run, in order, so tests can look.
    public private(set) var pushed: [[String]] = []
    public private(set) var executed: [[String]] = []
    /// Per VM, the SSH keys last applied, and what each apply ran: the program arguments and what went on standard input.
    public private(set) var sshKeys: [String: [String]] = [:]
    public private(set) var sshRuns: [(arguments: [String], input: Data)] = []
    private var sshdState: SshdState = .missing
    private var installFailure: SshdFailure?
    /// What each install of the SSH server ran: the program arguments.
    public private(set) var sshInstallRuns: [[String]] = []

    /// How an install of an app goes (set by tests), which apps each VM has, and what each install ran: the program arguments, and the script on standard input.
    private var appBehaviour: SimulatedAppInstall = .works
    private var installedApps: Set<String> = []
    public private(set) var appInstallRuns: [(arguments: [String], input: Data)] = []

    public init(capabilities: Capabilities = Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false)) {
        self.capabilities = capabilities
    }

    public static let engineName = "simulated"

    public func identity() async -> EngineIdentity { EngineIdentity(name: Self.engineName, version: nil) }

    public func list() async throws -> [Workload] {
        Array(store.values)
    }

    /// Makes every later create fail with this error, as a machine whose VMs do not start would.
    public func failCreates(_ error: EngineError?) { createFailure = error }

    public func failBackups(_ error: EngineError?) { backupError = error }

    public func failDeletes(_ error: EngineError?) { deleteError = error }

    public func failRestarts(_ error: EngineError?) { restartError = error }

    public func delayBackups(nanoseconds: UInt64) { backupDelayNanoseconds = nanoseconds }

    public func delayDeletes(nanoseconds: UInt64) { deleteDelayNanoseconds = nanoseconds }

    public func create(id: String, request: CreateWorkloadRequest) async throws -> Workload {
        if let createFailure { throw createFailure }
        let made = Workload(id: id, name: request.name, kind: request.kind, state: .running, cpu: request.cpu, ramMb: request.ramMb, diskGb: request.diskGb, gpuMode: request.gpuMode)
        store[id] = made
        return made
    }

    public func setRunning(id: String, running: Bool) async throws {
        lifecycleOperations.append("\(running ? "start" : "stop"):\(id)")
        if running, let restartError { throw restartError }
        try change(id) { $0.state = running ? .running : .stopped }
    }

    public func backup(id: String) async throws -> String {
        lifecycleOperations.append("backup:\(id)")
        try change(id) { _ in }
        if backupDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: backupDelayNanoseconds) }
        if let backupError { throw backupError }
        return "backup-\(id)"
    }

    public func delete(id: String) async throws {
        lifecycleOperations.append("delete:\(id)")
        guard store[id] != nil else { throw EngineError.notFound }
        if deleteDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: deleteDelayNanoseconds) }
        if let deleteError { throw deleteError }
        store[id] = nil
    }

    public func setBundleVersion(id: String, version: String?) async throws {
        try change(id) { $0.bundleVersion = version }
    }

    public func push(id: String, hostPath: String, containerPath: String) async throws {
        guard store[id] != nil else { throw EngineError.notFound }
        pushed.append([id, hostPath, containerPath])
    }

    public func exec(id: String, arguments: [String], environment: [String: String]) async throws -> String {
        guard store[id] != nil else { throw EngineError.notFound }
        executed.append(arguments)
        return ""
    }

    /// What every later SSH key apply reports about sshd, as the VM's image would decide it.
    public func setSshd(_ state: SshdState) { sshdState = state }

    /// Makes every later install of a missing SSH server fail with this reason (nil: installs work again).
    public func failSshdInstalls(_ failure: SshdFailure?) { installFailure = failure }

    public func installSshd(id: String) async throws -> SshdInstallReport {
        guard let found = store[id] else { throw EngineError.notFound }
        guard found.state == .running else { throw EngineError.notRunning }
        sshInstallRuns.append(SshdInstallScript.arguments(id: id))
        let missing = sshdState == .missing
        if missing, let installFailure { return SshdInstallReport(sshd: sshdState, installed: false, failure: installFailure) }
        sshdState = .running
        return SshdInstallReport(sshd: .running, installed: missing, failure: nil)
    }

    public func applySshKeys(id: String, keys: [String]) async throws -> SshKeysResult {
        guard let found = store[id] else { throw EngineError.notFound }
        guard found.state == .running else { throw EngineError.notRunning }
        let arguments = SshKeysScript.arguments(id: id)
        sshRuns.append((arguments: arguments, input: SshKeyLines.fileContent(keys)))
        sshKeys[id] = keys
        return SshKeysResult(applied: keys.count, sshd: sshdState)
    }

    /// How every later install of a missing app goes.
    public func setAppInstall(_ behaviour: SimulatedAppInstall) { appBehaviour = behaviour }

    public func hasApp(_ app: AppKind, id: String) -> Bool { installedApps.contains(Self.appKey(app, id)) }

    public func installApp(id: String, app: AppKind) async throws -> String {
        guard let found = store[id] else { throw EngineError.notFound }
        guard found.state == .running else { throw EngineError.notRunning }
        appInstallRuns.append((arguments: AppInstallCall.arguments(id: id), input: Data(app.script.utf8)))
        guard !hasApp(app, id: id) else { return SimulatedAppInstall.output(app, installed: false) }
        switch appBehaviour {
        case .works: return finishInstall(app, id: id)
        case .delay(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return finishInstall(app, id: id)
        case .fails(let failure): return SimulatedAppInstall.failureOutput(app, failure)
        case .garbage: return "something else entirely\n"
        case .breaks: throw EngineError.failed("engine-detail-xyz")
        }
    }

    private func finishInstall(_ app: AppKind, id: String) -> String {
        installedApps.insert(Self.appKey(app, id))
        return SimulatedAppInstall.output(app, installed: true)
    }

    private static func appKey(_ app: AppKind, _ id: String) -> String { "\(id)/\(app.rawValue)" }

    /// Tests type into a plain /bin/sh on this machine.
    public func attach(id: String) async throws -> [String] {
        guard store[id] != nil else { throw EngineError.notFound }
        return [Self.shellPath]
    }

    public static let shellPath = "/bin/sh"

    private func change(_ id: String, _ edit: (inout Workload) -> Void) throws {
        guard var found = store[id] else { throw EngineError.notFound }
        edit(&found)
        store[id] = found
    }
}
