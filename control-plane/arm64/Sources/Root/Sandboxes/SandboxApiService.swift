import Foundation
import RootCore
import RootStore

/// One sandbox as the public API just made it, or got it back: the reply and whether it had to be resumed.
struct SandboxApiAnswer {
    let sandbox: SandboxApiSandbox
    /// True when a paused sandbox was resumed, which the API answers with 201 instead of 200.
    let resumed: Bool
}

/// The public sandbox API's work, in the order `sandbox/README.md` sets out: the team's limits, then room on a machine, then
/// the machine itself, then the parent's record, then the audit. A refusal before the machine is never called; a refusal at the
/// machine leaves no record behind.
struct SandboxApiService {
    let services: Services
    let helper: SandboxHelperCalling

    /// The purpose the access token is derived under, so it can never collide with another signature the Root makes.
    static let accessTokenPurpose = "sandbox-access-token"

    // MARK: create

    func create(key: StoredApiKey, spec: SandboxCreateSpec) async throws -> SandboxApiAnswer {
        let (plan, limits) = try plan(for: spec, team: key.team)
        let started = try await start(plan, envVars: spec.envVars)
        let record = try await keep(plan, team: key.team, limits: limits)
        try auditCreated(record, key: key)
        return SandboxApiAnswer(sandbox: reply(record, envdVersion: started.daemonVersion), resumed: false)
    }

    /// Limits, placement and end time: all decided before anything is created, so a refusal costs one database read.
    private func plan(for spec: SandboxCreateSpec, team: String) throws -> (SandboxCreatePlan, TeamLimits) {
        guard let limits = try services.teams.limits(of: team) else { throw SandboxApiFailure.missingKey }
        let now = services.clock.now
        let usage = try services.sandboxes.teamUsage(team: team, now: now)
        let plan = try SandboxApiCreate.plan(spec: spec, limits: limits, usage: usage,
                                             machines: try machines(now: now), createdAt: now)
        return (plan, limits)
    }

    private func start(_ plan: SandboxCreatePlan, envVars: [String: String]) async throws -> HelperSandbox {
        let command = SandboxHelperCreate(id: plan.id, template: plan.template, shape: plan.shape, endAt: plan.endAt,
                                          envVars: envVars, accessToken: accessToken(plan.id))
        do {
            return try await helper.create(machine: plan.machine, command: command)
        } catch {
            throw Self.refusal(for: error)
        }
    }

    /// The record, written only once the sandbox is running. The store checks the limits again in the same transaction, because
    /// another create may have taken the room in between; when it refuses, what was started is removed again so nothing is left
    /// running without a record.
    private func keep(_ plan: SandboxCreatePlan, team: String, limits: TeamLimits) async throws -> SandboxRecord {
        let new = NewSandbox(id: plan.id, team: team, machine: plan.machine, template: plan.template, shape: plan.shape,
                             endAt: plan.endAt, state: .running)
        do {
            return try services.sandboxes.create(new, limits: limits, now: services.clock.now)
        } catch let refusal as TeamLimitRefusal {
            await undo(plan)
            throw SandboxApiFailure.teamLimit(refusal)
        } catch {
            await undo(plan)
            throw SandboxApiFailure(status: 500, message: "The sandbox ran, but it could not be recorded; it was removed again.")
        }
    }

    // MARK: list and one

    func list(team: String, query: SandboxListQuery) throws -> [SandboxApiListed] {
        try services.sandboxes.list(team: team, limit: query.limit)
            .filter { $0.isAlive && (query.states?.contains($0.state) ?? true) }
            .map { listed($0) }
    }

    func detail(team: String, id: String) throws -> SandboxApiDetail {
        detail(of: try own(team: team, id: id))
    }

    // MARK: end, timeout, connect

    func remove(team: String, id: String, key: StoredApiKey) async throws {
        let record = try own(team: team, id: id)
        do {
            try await helper.delete(machine: record.machine, id: record.id)
        } catch SandboxHelperError.refused(let status, _, _) where status == AgentSandboxHelper.notFound {
            // Already gone at the machine: the record still has to be closed, or the team's room never comes back.
        } catch {
            throw Self.refusal(for: error)
        }
        try finish(record, reason: .deleted, actor: Self.actor(key))
    }

    func setTimeout(team: String, id: String, body: SandboxApiTimeoutBody, key: StoredApiKey) async throws {
        let record = try own(team: team, id: id)
        let now = services.clock.now
        guard body.timeoutSeconds > 0 else {
            try await helper.setEnd(machine: record.machine, id: record.id, endAt: now)
            try finish(record, reason: .timeout, actor: Self.actor(key))
            return
        }
        let endAt = try endTime(of: record, now: now, timeoutSeconds: body.timeoutSeconds)
        try await setEnd(record, to: endAt)
        try services.audit.record(actor: Self.actor(key), action: SandboxAudit.sandboxTimeout, target: record.id,
                                  detail: SandboxAudit.changeDetail(team: team, machine: record.machine, endAt: endAt, prefix: key.prefix),
                                  at: now)
    }

    /// Get a running sandbox, resuming it first if it is paused, and set its timeout (as E2B's connect does).
    func connect(team: String, id: String, body: SandboxApiConnectBody, key: StoredApiKey) async throws -> SandboxApiAnswer {
        let record = try own(team: team, id: id)
        let before = try await state(record)
        let endAt = try endTime(of: record, now: services.clock.now, timeoutSeconds: body.timeoutSeconds)
        try await setEnd(record, to: endAt)
        let resumed = before.state == .paused
        let after = resumed ? try await resume(record) : before
        try services.audit.record(actor: Self.actor(key), action: SandboxAudit.sandboxConnected, target: record.id,
                                  detail: SandboxAudit.changeDetail(team: team, machine: record.machine, endAt: endAt, prefix: key.prefix),
                                  at: services.clock.now)
        let current = try own(team: team, id: id)
        return SandboxApiAnswer(sandbox: reply(current, envdVersion: after.daemonVersion), resumed: resumed)
    }

    /// Save the whole sandbox and stop it. An already paused sandbox is the API's 409, not a second pause.
    func pause(team: String, id: String, key: StoredApiKey) async throws {
        let record = try own(team: team, id: id)
        do {
            _ = try await helper.pause(machine: record.machine, id: record.id)
        } catch SandboxHelperError.refused(let status, _, _) where status == AgentSandboxHelper.notPausable {
            throw SandboxApiFailure(status: 409, message: "This sandbox is already paused.")
        } catch {
            throw Self.refusal(for: error)
        }
        _ = try services.sandboxes.setState(id: record.id, state: .paused)
        try services.audit.record(actor: Self.actor(key), action: SandboxAudit.sandboxPaused, target: record.id,
                                  detail: SandboxAudit.changeDetail(team: team, machine: record.machine, endAt: record.endAt, prefix: key.prefix),
                                  at: services.clock.now)
    }

    /// The helper's readings, forwarded as they came. A sandbox of another team is "no such sandbox" before any call is made.
    func metrics(team: String, id: String, from: Int?, until: Int?) async throws -> [[String: Any]] {
        let record = try own(team: team, id: id)
        do {
            return try await helper.metrics(machine: record.machine, id: record.id, from: from, until: until)
        } catch {
            throw Self.refusal(for: error)
        }
    }

    // MARK: the panel's actions

    /// The panel's kill: an operator may end any team's sandbox, so no team is asked. The record is closed, the run is counted
    /// in the usage ledger, and the audit entry names the operator.
    func operatorKill(id: String, actor: String) async throws {
        let record = try alive(id: id)
        do {
            try await helper.delete(machine: record.machine, id: record.id)
        } catch SandboxHelperError.refused(let status, _, _) where status == AgentSandboxHelper.notFound {
            // Already gone at the machine: the record still has to be closed, or the team's room never comes back.
        } catch {
            throw Self.refusal(for: error)
        }
        try finish(record, reason: .deleted, actor: actor, action: SandboxAudit.sandboxKilled)
    }

    /// The panel's pause: a sandbox that has ended is no such sandbox, and one already paused is the panel's 409.
    func operatorPause(id: String, actor: String) async throws {
        let record = try alive(id: id)
        if let refusal = SandboxPanelActions.refusal(.pause, sandbox: record.owner) {
            throw SandboxApiFailure(status: 409, message: refusal.message, errorCode: refusal.rawValue)
        }
        do {
            _ = try await helper.pause(machine: record.machine, id: record.id)
        } catch SandboxHelperError.refused(let status, _, _) where status == AgentSandboxHelper.notPausable {
            throw SandboxApiFailure.notPausable
        } catch {
            throw Self.refusal(for: error)
        }
        _ = try services.sandboxes.setState(id: record.id, state: .paused)
        try services.audit.record(actor: actor, action: SandboxAudit.sandboxPaused, target: record.id,
                                  detail: SandboxAudit.actionDetail(team: record.team, machine: record.machine), at: services.clock.now)
    }

    // MARK: the record

    /// The record, when it is this team's and still alive. Ended and unknown are the same answer: there is no such sandbox.
    private func own(team: String, id: String) throws -> SandboxRecord {
        guard let record = try services.sandboxes.get(id: id), SandboxOwnership.permits(team: team, sandbox: record.owner) else {
            throw SandboxApiFailure.noSuchSandbox()
        }
        return record
    }

    /// The record, when it exists and has not ended. The panel acts for the operator, who sees every team, so no team is asked.
    private func alive(id: String) throws -> SandboxRecord {
        guard let record = try services.sandboxes.get(id: id), record.isAlive else { throw SandboxApiFailure.noSuchSandbox() }
        return record
    }

    /// Closes the record, counts the run and writes one audit entry. `action` tells an operator's kill from a program's delete.
    private func finish(_ record: SandboxRecord, reason: SandboxEndReason, actor: String,
                        action: String = SandboxAudit.sandboxEnded) throws {
        let now = services.clock.now
        _ = try services.sandboxes.end(id: record.id, at: now, reason: reason)
        let seconds = SandboxUsageMath.seconds(from: record.createdAt, to: now)
        try services.sandboxUsage.record(team: record.team, sandbox: record.id, startedAt: record.createdAt, endedAt: now, shape: record.shape)
        try services.audit.record(actor: actor, action: action, target: record.id,
                                  detail: SandboxAudit.endDetail(team: record.team, machine: record.machine, reason: reason, seconds: seconds),
                                  at: now)
    }

    private func endTime(of record: SandboxRecord, now: Date, timeoutSeconds: Int) throws -> Date {
        do {
            return try SandboxEndTime.end(createdAt: record.createdAt, now: now, timeoutSeconds: timeoutSeconds)
        } catch let refusal as SandboxEndTime.Refusal {
            throw SandboxApiFailure.endTime(refusal)
        }
    }

    // MARK: the machine

    private func state(_ record: SandboxRecord) async throws -> HelperSandbox {
        do {
            return try await helper.sandbox(machine: record.machine, id: record.id)
        } catch {
            throw Self.refusal(for: error)
        }
    }

    private func resume(_ record: SandboxRecord) async throws -> HelperSandbox {
        do {
            return try await helper.resume(machine: record.machine, id: record.id)
        } catch SandboxHelperError.refused(let status, let code, _) where status == AgentSandboxHelper.notPausable || code == SandboxApiCodes.notPausable {
            throw SandboxApiFailure.notPausable
        } catch {
            throw Self.refusal(for: error)
        }
    }

    private func setEnd(_ record: SandboxRecord, to endAt: Date) async throws {
        do {
            try await helper.setEnd(machine: record.machine, id: record.id, endAt: endAt)
        } catch {
            throw Self.refusal(for: error)
        }
        _ = try services.sandboxes.moveEnd(id: record.id, to: endAt)
    }

    /// Remove what a create started when the parent cannot keep it. Best effort: if the machine cannot be reached the
    /// sandbox still ends at its own end time, because the helper keeps that itself.
    private func undo(_ plan: SandboxCreatePlan) async {
        try? await helper.delete(machine: plan.machine, id: plan.id)
    }

    // MARK: replies

    private func reply(_ record: SandboxRecord, envdVersion: String?) -> SandboxApiSandbox {
        let version = envdVersion.flatMap { SandboxApiDefaults.isVersion($0) ? $0 : nil } ?? SandboxApiDefaults.envdVersion
        return SandboxApiSandbox(templateID: record.template, sandboxID: record.id, envdVersion: version,
                                 envdAccessToken: accessToken(record.id), domain: services.config.sandboxDomain)
    }

    private func detail(of record: SandboxRecord) -> SandboxApiDetail {
        SandboxApiDetail(templateID: record.template, sandboxID: record.id, startedAt: Self.iso(record.createdAt),
                         endAt: Self.iso(record.endAt), cpuCount: record.vcpu, memoryMB: record.ramMb, diskSizeMB: record.diskMb,
                         envdVersion: SandboxApiDefaults.envdVersion, domain: services.config.sandboxDomain,
                         state: SandboxApiState.name(for: record.state))
    }

    private func listed(_ record: SandboxRecord) -> SandboxApiListed {
        SandboxApiListed(templateID: record.template, sandboxID: record.id, startedAt: Self.iso(record.createdAt),
                         endAt: Self.iso(record.endAt), cpuCount: record.vcpu, memoryMB: record.ramMb, diskSizeMB: record.diskMb,
                         envdVersion: SandboxApiDefaults.envdVersion, state: SandboxApiState.name(for: record.state))
    }

    // MARK: small pieces

    /// The token the program sends to the daemon inside. Derived from the Root's own secret and the sandbox id (as E2B does),
    /// so create and connect give the same token back without the parent storing it.
    private func accessToken(_ sandboxID: String) -> String {
        services.secrets.signature(sandboxID, purpose: Self.accessTokenPurpose)
    }

    private func machines(now: Date) throws -> [SandboxMachine] {
        try services.machines.list(now: now).map {
            SandboxMachine(id: $0.id, online: $0.state != MachineState.offline.rawValue, capabilities: $0.capabilities, facts: $0.sandbox)
        }
    }

    private func auditCreated(_ record: SandboxRecord, key: StoredApiKey) throws {
        try services.audit.record(actor: Self.actor(key), action: SandboxAudit.sandboxCreated, target: record.id,
                                  detail: SandboxAudit.createDetail(team: record.team, machine: record.machine, template: record.template,
                                                                    shape: record.shape, endAt: record.endAt),
                                  at: services.clock.now)
    }

    /// The audit log names the key by its prefix, which is not secret, and never the key itself.
    private static func actor(_ key: StoredApiKey) -> String { "sandbox-key:\(key.prefix)" }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func refusal(for error: Error) -> SandboxApiFailure {
        switch error {
        case SandboxHelperError.unreachable:
            return .helperUnreachable
        case SandboxHelperError.refused(let status, let code, let message):
            return .helper(status: status, errorCode: code, message: message)
        default:
            return .helperUnreachable
        }
    }
}
