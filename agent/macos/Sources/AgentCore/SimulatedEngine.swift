import Foundation

/// An engine that only pretends. Used to test the Agent on a machine that has no virtualization tool, and by the conformance suite.
public actor SimulatedEngine: Engine {
    public nonisolated let capabilities: Capabilities
    private var store: [String: Workload] = [:]
    private var createFailure: EngineError?
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

    public func create(id: String, request: CreateWorkloadRequest) async throws -> Workload {
        if let createFailure { throw createFailure }
        let made = Workload(id: id, name: request.name, kind: request.kind, state: .running, cpu: request.cpu, ramMb: request.ramMb, diskGb: request.diskGb, gpuMode: request.gpuMode)
        store[id] = made
        return made
    }

    public func setRunning(id: String, running: Bool) async throws {
        try change(id) { $0.state = running ? .running : .stopped }
    }

    public func backup(id: String) async throws -> String {
        try change(id) { _ in }
        return "backup-\(id)"
    }

    public func delete(id: String) async throws {
        guard store.removeValue(forKey: id) != nil else { throw EngineError.notFound }
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
