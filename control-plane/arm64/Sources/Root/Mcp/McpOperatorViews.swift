import Foundation
import RootCore
import RootStore

/// The JSON the panel reads (mcp/SPEC.md sections 7.1 and 10). Snake case, times in ISO 8601, never a token text or a hash.
extension McpService {
    static func iso(_ date: Date?) -> Any { date.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull() }

    func tokenView(_ token: McpTokenRecord) -> [String: Any] {
        let person = try? people.get(id: token.personId)
        return ["id": token.id, "name": token.name, "prefix": token.prefix, "person_id": token.personId, "person_name": Self.null(person?.name), "scopes": McpScope.names(token.scopes),
                "created_by": token.createdBy, "created_at": Self.iso(token.createdAt), "expires_at": Self.iso(token.expiresAt), "last_used_at": Self.iso(token.lastUsedAt),
                "revoked_at": Self.iso(token.revokedAt), "status": token.refusal(at: clock.now) ?? "active", "client_name": Self.null(token.clientName), "client_version": Self.null(token.clientVersion)]
    }

    func personView(_ person: McpPersonRecord) -> [String: Any] {
        let alive = (try? ownership.usage(person: person.id, now: clock.now).aliveVms) ?? 0
        return ["id": person.id, "name": person.name, "scopes": McpScope.names(person.scopes), "quotas": person.quotas.json, "tokens": (try? tokens.liveCount(person: person.id)) ?? 0,
                "vms_alive": alive, "last_used_at": Self.iso((try? tokens.lastUsed(person: person.id)) ?? nil), "created_at": Self.iso(person.createdAt), "disabled_at": Self.iso(person.disabledAt)]
    }

    /// `{at, actor, person, action, target, status}`: an audit row of a person's token, with the status its detail carries.
    func activityView(_ entry: AuditEntry) -> [String: Any] {
        let detail = (try? JSONSerialization.jsonObject(with: Data(entry.detail.utf8))) as? [String: Any]
        return ["at": entry.ts, "actor": entry.actor, "person": String(entry.actor.dropFirst("mcp:".count)), "action": entry.action, "target": Self.null(entry.target),
                "status": detail?["status"] as? String ?? "ok", "token_prefix": Self.null(detail?["token_prefix"] as? String), "client": Self.null(detail?["client"] as? String)]
    }

    func infoView() -> [String: Any] {
        let base = publicBaseURL.hasSuffix("/") ? String(publicBaseURL.dropLast()) : publicBaseURL
        return ["endpoint": base + "/mcp", "protocol_versions": McpProtocol.supportedVersions, "scopes": McpScope.allCases.map(\.rawValue), "tools": McpTool.names,
                "defaults": ["scopes": McpScope.names(McpScope.defaults), "quotas": McpQuotas.defaults.json, "expires_in_days": McpTokenRequest.defaultExpiryDays,
                             "max_expires_in_days": Self.maxExpiryDays] as [String: Any]]
    }
}
