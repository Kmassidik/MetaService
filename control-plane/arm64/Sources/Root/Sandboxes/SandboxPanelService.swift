import Foundation
import HTTPTypes
import MSCore
import RootCore
import RootStore

/// The operator's sandbox work: teams and keys, the live list, one action on a sandbox, and the usage totals. Every change is
/// audited under the operator's name. A key's text leaves this type exactly once, in `makeKey`.
struct SandboxPanelService {
    let services: Services
    let helper: SandboxHelperCalling

    /// The most rows one page reads; the same cap the stores keep.
    static let listLimit = 200
    /// The audit log names a panel caller this way, so its entries are told apart from a program's key.
    static let actorPrefix = "operator:"

    static func actor(_ name: String) -> String { "\(actorPrefix)\(name)" }

    // MARK: teams and keys

    func keys() throws -> SandboxKeyList {
        let names = try teamNames()
        let keys = try services.apiKeys.listAll(limit: Self.listLimit)
        return SandboxKeyList(keys: keys.map { SandboxKeyListed(record: $0, teamName: names[$0.team] ?? $0.team) })
    }

    /// Makes a key for the team the operator named. A name that is not a team yet becomes one, created with the standard
    /// limits, so a key is never left without a team; no name at all means the default team, made the same way.
    func makeKey(teamName typed: String?, actor: String) throws -> SandboxKeyMade {
        let team = try team(named: try requestedName(typed), actor: actor)
        let id = PanelApiKey.newId()
        let made = PanelApiKey.issue()
        let now = services.clock.now
        try services.apiKeys.create(id: id, team: team.id, prefix: made.prefix, secretHash: made.secretHash, now: now)
        try services.audit.record(actor: actor, action: SandboxAudit.keyCreated, target: id,
                                  detail: SandboxAudit.keyDetail(team: team.id, prefix: made.prefix), at: now)
        return SandboxKeyMade(id: id, team: team.id, teamName: team.name, prefix: made.prefix, key: made.text,
                              createdAt: SandboxPanelTime.iso(now))
    }

    /// Revokes a key of any team. A key that was already revoked is left as it is and writes no second audit entry.
    func revokeKey(id: String, actor: String) throws {
        guard let key = try services.apiKeys.get(id: id) else { throw ApiFailure.notFound }
        guard try services.apiKeys.revoke(id: key.id, team: key.team, now: services.clock.now) else { return }
        try services.audit.record(actor: actor, action: SandboxAudit.keyRevoked, target: key.id,
                                  detail: SandboxAudit.keyDetail(team: key.team, prefix: key.prefix), at: services.clock.now)
    }

    /// The team a key is made for: the one with this name, or a new one. Others read the same team by its name, so a name
    /// typed differently in case still means the same team.
    private func team(named name: String, actor: String) throws -> TeamRecord {
        if let existing = try services.teams.findByName(name) { return existing }
        let record = try services.teams.create(id: try freeTeamId(from: name), name: name, now: services.clock.now)
        try services.audit.record(actor: actor, action: SandboxAudit.teamCreated, target: record.id,
                                  detail: SandboxAudit.teamDetail(name: record.name, limits: record.limits), at: services.clock.now)
        return record
    }

    /// The name the operator asked for, or the default team's name when the field was left empty. A name that cannot be kept
    /// as typed is refused before anything is written.
    private func requestedName(_ typed: String?) throws -> String {
        let text = (typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return SandboxTeamRules.defaultTeamName }
        guard let name = SandboxTeamRules.cleanName(text) else { throw ApiFailure.invalid(SandboxTeamRules.nameRule) }
        return name
    }

    /// The id a new team is kept under: the name's own id when it is free, or the first free numbered one after it.
    private func freeTeamId(from name: String) throws -> String {
        let base = SandboxTeamRules.id(from: name)
        if try services.teams.get(base) == nil { return base }
        for number in 2...SandboxTeamRules.idAttempts {
            let candidate = SandboxTeamRules.numbered(base, number)
            if try services.teams.get(candidate) == nil { return candidate }
        }
        throw ApiFailure(status: .conflict, code: "team_name_taken", message: "There are too many teams with that name; give this one a different name.")
    }

    private func teamNames() throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try services.teams.list().map { ($0.id, $0.name) })
    }

    // MARK: sandboxes

    /// Every sandbox still alive, across teams, with the team's name so the panel needs no second call.
    func sandboxes() throws -> SandboxLiveList {
        let names = try teamNames()
        return SandboxLiveList(sandboxes: try services.sandboxes.listAlive(limit: Self.listLimit).map {
            SandboxListed(record: $0, teamName: names[$0.team] ?? $0.team)
        })
    }

    /// Ends a sandbox and everything inside it. Refused when it has already ended.
    func kill(id: String, actor: String) async throws {
        try await apiCall { try await $0.operatorKill(id: id, actor: actor) }
    }

    /// Saves a sandbox and stops it, memory and all. Refused when it has already ended or is already paused.
    func pause(id: String, actor: String) async throws {
        try await apiCall { try await $0.operatorPause(id: id, actor: actor) }
    }

    private func apiCall(_ work: (SandboxApiService) async throws -> Void) async throws {
        do {
            try await work(SandboxApiService(services: services, helper: helper))
        } catch let failure as SandboxApiFailure {
            throw Self.panelFailure(failure)
        }
    }

    // MARK: usage

    /// What each team's finished runs used in the window. Teams with no finished run in the window are not listed.
    func usage(days requested: Int?) throws -> SandboxUsageReply {
        guard let days = SandboxUsageWindow.days(from: requested) else {
            throw ApiFailure.invalid("days must be a whole number from 1 to \(SandboxUsageWindow.longestDays).")
        }
        let now = services.clock.now
        let start = SandboxUsageWindow.start(now: now, days: days)
        let names = try teamNames()
        let rows = try services.sandboxUsage.totalsByTeam(from: start, to: now, limit: Self.listLimit)
        return SandboxUsageReply(days: days, startsAt: SandboxPanelTime.iso(start), endsAt: SandboxPanelTime.iso(now),
                                 teams: rows.map { SandboxUsageTeam(record: $0, teamName: names[$0.team] ?? $0.team) })
    }

    /// The panel's own answer for something the sandbox API refused: the same status, a code the page can read and a plain
    /// message. A helper that cannot be reached stays a 503, so the page says the machine could not be reached.
    static func panelFailure(_ failure: SandboxApiFailure) -> ApiFailure {
        ApiFailure(status: HTTPResponse.Status(code: failure.status), code: failure.errorCode ?? "refused", message: failure.message)
    }
}
