import Foundation
import RootCore
import RootStore

/// The MCP server's working parts: the token, workload and request stores, and the services the nine tools are thin adapters over.
/// The tools, the follow-up of requests, the approvals and the operator side are extensions in the files beside this one.
final class McpService: @unchecked Sendable {
    let tokens: McpTokenStore
    let people: McpPeopleStore
    let ownership: McpWorkloadStore
    let requests: McpRequestStore
    let activity: McpActivityStore
    let origins: VmOriginStore
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

    static let maxExpiryDays = McpTokenRequest.expiryDays.upperBound

    init(database: Database, machines: MachineStore, commands: CommandStore, audit: AuditStore, workloads: WorkloadService, sshKeys: SshKeyService, terminal: TerminalService,
         origins: VmOriginStore, throttle: Throttle, clock: Clock, publicBaseURL: String) {
        tokens = McpTokenStore(database)
        people = McpPeopleStore(database)
        ownership = McpWorkloadStore(database)
        requests = McpRequestStore(database)
        activity = McpActivityStore(database)
        self.origins = origins
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

    /// Who is behind a Bearer text, or nil when the token is missing, unknown, revoked or expired, or its person is disabled (all one 401 for the caller).
    /// A good token notes its use.
    func authenticate(bearer: String?, sourceIp: String) throws -> McpCaller? {
        guard let bearer, McpToken.isWellFormed(bearer), let token = try tokens.find(hash: McpToken.hash(bearer)) else { return nil }
        guard token.refusal(at: clock.now) == nil, let person = try people.get(id: token.personId), !person.isDisabled else { return nil }
        try tokens.touch(id: token.id, now: clock.now)
        return McpCaller(token: token, person: person, sourceIp: sourceIp)
    }

    // MARK: what a token may see

    func isShared(_ machine: MachineSummary) -> Bool { McpShared.isShared(ip: machine.ip) }

    /// A shared machine is invisible to a token without the `shared` scope, as if it did not exist.
    func canSee(_ machine: MachineSummary, caller: McpCaller) -> Bool {
        !isShared(machine) || caller.scopes.contains(.shared)
    }

    func visibleMachines(for caller: McpCaller) throws -> [MachineSummary] {
        try machines.list(now: clock.now).filter { canSee($0, caller: caller) }
    }

    func machine(_ id: String, for caller: McpCaller) throws -> MachineSummary {
        guard let found = try? machines.get(id: id, now: clock.now), canSee(found, caller: caller) else { throw McpRefusal.noMachine }
        return found
    }

    // MARK: audit and ids

    /// One audit row per tool call: who (`mcp:<person>`), what (`mcp.<tool>`), where, and how it ended; the detail names the token by its prefix and the client by
    /// what it called itself. Never the arguments and never the token.
    func record(_ caller: McpCaller, tool: String, status: String, target: String?, detail: [String: String] = [:]) {
        var fields = detail
        fields["status"] = status
        fields["token_prefix"] = caller.token.prefix
        fields["client"] = caller.token.clientName
        try? audit.record(actor: caller.actor, action: "mcp.\(tool)", target: target, detail: fields, at: clock.now)
    }

    static func newId(_ prefix: String) -> String {
        prefix + Tokens.random(bytes: 9).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(12)
    }
}

/// Who is calling: the token, the person it belongs to, and where the call came from. The person's quotas and VMs are the caller's; the scopes are the overlap of the
/// token's and the person's, so taking a scope from a person takes it from every token at once.
struct McpCaller {
    let token: McpTokenRecord
    let person: McpPersonRecord
    let sourceIp: String

    var scopes: Set<McpScope> { token.scopes.intersection(person.scopes) }
    var quotas: McpQuotas { person.quotas }
    var actor: String { person.actor }

    /// The creator record of a VM this call asks for.
    func origin(request: String) -> VmOriginInput {
        VmOriginInput(kind: .mcp, actor: actor, personId: person.id, personName: person.name, tokenId: token.id, tokenPrefix: token.prefix,
                      clientName: token.clientName, clientVersion: token.clientVersion, sourceIp: sourceIp, requestId: request)
    }
}
