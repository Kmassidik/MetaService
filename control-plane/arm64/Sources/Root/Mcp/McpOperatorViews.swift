import Foundation
import RootCore
import RootStore

/// The JSON the panel reads (mcp/SPEC.md section 7.1). Snake case, times in ISO 8601, never a token text or a hash.
extension McpService {
    static func iso(_ date: Date?) -> Any { date.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull() }

    func tokenView(_ token: McpTokenRecord) -> [String: Any] {
        let status = token.refusal(at: clock.now) ?? "active"
        let alive = (try? ownership.usage(token: token.id, now: clock.now).aliveVms) ?? 0
        return ["id": token.id, "name": token.name, "prefix": token.prefix, "scopes": McpScope.names(token.scopes), "quotas": token.quotas.json, "auto_approve": token.autoApprove,
                "created_by": token.createdBy, "created_at": Self.iso(token.createdAt), "expires_at": Self.iso(token.expiresAt), "last_used_at": Self.iso(token.lastUsedAt),
                "revoked_at": Self.iso(token.revokedAt), "status": status, "vms_alive": alive]
    }

    /// The request for a person: the plain sentence of the exact action, why it waits, and the details with the names the panel prefers.
    /// The public key and the approval reason are not among the details.
    func approvalView(_ request: McpRequestRow) -> [String: Any] {
        var params = request.params
        let reason = params.removeValue(forKey: "approval_reason")
        params.removeValue(forKey: "ssh_public_key")
        let machineId = params["machine"] as? String
        if params["machine_name"] == nil, let machineId, let machine = try? machines.get(id: machineId, now: clock.now) { params["machine_name"] = machine.name }
        let tokenName = (try? tokens.get(id: request.tokenId))?.name ?? "unknown"
        return ["id": request.id, "token_id": request.tokenId, "token_name": tokenName, "kind": request.kind.rawValue,
                "description": McpDescribe.action(kind: request.kind.rawValue, params: request.params), "reason": Self.null(reason), "params": params, "state": request.state.rawValue,
                "created_at": Self.iso(request.createdAt), "expires_at": Self.iso(request.expiresAt), "decided_by": Self.null(request.decidedBy), "decided_at": Self.iso(request.decidedAt),
                "message": Self.null(request.result?["message"])]
    }

    /// `{at, actor, action, target, status}`: an audit row of a token, with the status its detail carries.
    func activityView(_ entry: AuditEntry) -> [String: Any] {
        let detail = (try? JSONSerialization.jsonObject(with: Data(entry.detail.utf8))) as? [String: Any]
        return ["at": entry.ts, "actor": entry.actor, "action": entry.action, "target": Self.null(entry.target), "status": detail?["status"] as? String ?? "ok"]
    }

    func infoView() -> [String: Any] {
        let base = publicBaseURL.hasSuffix("/") ? String(publicBaseURL.dropLast()) : publicBaseURL
        return ["endpoint": base + "/mcp", "protocol_versions": McpProtocol.supportedVersions, "scopes": McpScope.allCases.map(\.rawValue), "tools": McpTool.names,
                "defaults": ["scopes": McpScope.names(McpScope.defaults), "quotas": McpQuotas.defaults.json, "expires_in_days": Self.defaultExpiryDays,
                             "max_expires_in_days": Self.maxExpiryDays, "auto_approve": false] as [String: Any]]
    }
}
