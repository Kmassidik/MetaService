import Foundation
import RootCore
import RootStore

/// The MCP server's working parts: the token, workload and request stores, and the services the nine tools are thin adapters over.
/// The tools, the follow-up of requests, the approvals and the operator side are extensions in the files beside this one.
final class McpService: @unchecked Sendable {
    let tokens: McpTokenStore
    let ownership: McpWorkloadStore
    let requests: McpRequestStore
    let activity: McpActivityStore
    let machines: MachineStore
    let commands: CommandStore
    let audit: AuditStore
    let workloads: WorkloadService
    let sshKeys: SshKeyService
    let terminal: TerminalService
    let throttle: Throttle
    let clock: Clock
    let publicBaseURL: String
    /// Held while a create checks the quotas and reserves its slot, so two creates at once cannot both take the last one. Never held across an await.
    let reserving = NSLock()

    static let defaultExpiryDays = 90
    static let maxExpiryDays = 365

    init(database: Database, machines: MachineStore, commands: CommandStore, audit: AuditStore, workloads: WorkloadService, sshKeys: SshKeyService, terminal: TerminalService,
         throttle: Throttle, clock: Clock, publicBaseURL: String) {
        tokens = McpTokenStore(database)
        ownership = McpWorkloadStore(database)
        requests = McpRequestStore(database)
        activity = McpActivityStore(database)
        self.machines = machines
        self.commands = commands
        self.audit = audit
        self.workloads = workloads
        self.sshKeys = sshKeys
        self.terminal = terminal
        self.throttle = throttle
        self.clock = clock
        self.publicBaseURL = publicBaseURL
    }

    /// The token behind a Bearer text, or nil when it is missing, unknown, revoked or expired (all one 401 for the caller). A good token notes its use.
    func authenticate(bearer: String?) throws -> McpTokenRecord? {
        guard let bearer, McpToken.isWellFormed(bearer), let token = try tokens.find(hash: McpToken.hash(bearer)) else { return nil }
        guard token.refusal(at: clock.now) == nil else { return nil }
        try tokens.touch(id: token.id, now: clock.now)
        return token
    }

    // MARK: what a token may see

    func isShared(_ machine: MachineSummary) -> Bool { McpShared.isShared(ip: machine.ip) }

    /// A shared machine is invisible to a token without the `shared` scope, as if it did not exist.
    func canSee(_ machine: MachineSummary, token: McpTokenRecord) -> Bool {
        !isShared(machine) || token.scopes.contains(.shared)
    }

    func visibleMachines(for token: McpTokenRecord) throws -> [MachineSummary] {
        try machines.list(now: clock.now).filter { canSee($0, token: token) }
    }

    func machine(_ id: String, for token: McpTokenRecord) throws -> MachineSummary {
        guard let found = try? machines.get(id: id, now: clock.now), canSee(found, token: token) else { throw McpRefusal.noMachine }
        return found
    }

    // MARK: audit and ids

    /// One audit row per tool call: who (`mcp:<token name>`), what (`mcp.<tool>`), where, and how it ended. Never the arguments and never the token.
    func record(_ token: McpTokenRecord, tool: String, status: String, target: String?, detail: [String: String] = [:]) {
        var fields = detail
        fields["status"] = status
        try? audit.record(actor: token.actor, action: "mcp.\(tool)", target: target, detail: fields, at: clock.now)
    }

    static func newId(_ prefix: String) -> String {
        prefix + Tokens.random(bytes: 9).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(12)
    }
}
