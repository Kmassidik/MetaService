import Foundation

/// What an Agent needs from the machine's virtualization layer. One implementation per OS; the Agent logic above it is shared.
public protocol Engine: Sendable {
    var capabilities: Capabilities { get }
    /// What this engine is, for the facts: a short name and its version, or nil when it cannot tell. Never guessed.
    func identity() async -> EngineIdentity
    /// What on this machine stops it from running workloads right now. Empty means ready.
    var problems: [HostProblem] { get }
    func list() async throws -> [Workload]
    func create(id: String, request: CreateWorkloadRequest) async throws -> Workload
    func setRunning(id: String, running: Bool) async throws
    /// Copies the workload's disk somewhere safe and returns the backup's name. Called before every delete.
    func backup(id: String) async throws -> String
    func delete(id: String) async throws
    /// Records which chat bundle version a workload has (nil: none, the chat was turned off).
    func setBundleVersion(id: String, version: String?) async throws
    /// Copies a file from this machine into the workload.
    func push(id: String, hostPath: String, containerPath: String) async throws
    /// Runs one program inside the workload (no shell is added) and returns what it printed. Values go in through `environment`, never into the arguments.
    func exec(id: String, arguments: [String], environment: [String: String]) async throws -> String
    /// Replaces the whole list of SSH public keys that may log in as root of this one VM. The keys go in on standard input, never in arguments.
    /// Throws `notFound` for an unknown VM and `notRunning` for one that is not running.
    func applySshKeys(id: String, keys: [String]) async throws -> SshKeysResult
    /// Installs (when missing), locks to keys only, and starts the SSH server inside one running VM, with a fixed script and no request data. The keys were written before.
    /// Throws `SshdFailure` when the server could not be made to listen, `notFound` for an unknown VM and `notRunning` for one that is not running.
    func installSshd(id: String) async throws -> SshdInstallReport
    /// The program and arguments that open an interactive shell inside the workload, to be run in a pty. The first item is the program. No shell string, no user text.
    func attach(id: String) async throws -> [String]
}

/// The name and version of the program a machine makes VMs with.
public struct EngineIdentity: Equatable, Sendable {
    public let name: String
    public let version: String?

    public init(name: String, version: String?) {
        self.name = name
        self.version = version
    }
}

public extension Engine {
    var problems: [HostProblem] { [] }
}

public enum EngineError: Error, Equatable {
    case notFound
    /// The VM exists but is not running, so nothing can be run inside it.
    case notRunning
    case failed(String)
    /// The VM was made but never came up. The text is written by the helper (it may hold the last lines the VM printed, cleaned) and is safe to show the person.
    case notReady(String)
}
