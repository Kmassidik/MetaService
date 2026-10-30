import Foundation
import RootCore
import RootStore

/// A person's yes or no on a stored request. A token can never approve anything: only the panel's operator routes reach these.
extension McpService {
    /// Runs the stored action as `mcp:<token name>`, approved by the operator. The answer is the request as it stands afterwards (`running`, `done` or `failed`).
    func approve(_ id: String, operatorName: String) async throws -> McpRequestRow {
        let (request, token) = try pendingRequest(id)
        guard token.refusal(at: clock.now) == nil else {
            try? requests.finish(id: id, state: .failed, result: ["message": "The token was revoked or has expired, so this was not run."])
            throw ApiFailure(status: .conflict, code: "token_not_usable", message: "the token was revoked or has expired")
        }
        guard try requests.decide(id: id, to: .approved, by: operatorName, now: clock.now) else { throw Self.notPending }
        try audit.record(actor: operatorName, action: "mcp.approve", target: id, detail: ["token": token.name, "kind": request.kind.rawValue], at: clock.now)
        await run(request, token: token, approvedBy: operatorName)
        settle(token)
        return try requests.get(id: id) ?? request
    }

    func deny(_ id: String, operatorName: String) throws -> McpRequestRow {
        let (request, token) = try pendingRequest(id)
        guard try requests.decide(id: id, to: .denied, by: operatorName, now: clock.now) else { throw Self.notPending }
        try audit.record(actor: operatorName, action: "mcp.deny", target: id, detail: ["token": token.name, "kind": request.kind.rawValue], at: clock.now)
        record(token, tool: "\(request.kind.rawValue)_vm", status: "denied", target: request.params["machine"] as? String, detail: ["request": id, "denied_by": operatorName])
        return try requests.get(id: id) ?? request
    }

    private static let notPending = ApiFailure(status: .conflict, code: "not_pending", message: "this request was already decided or has expired")

    private func pendingRequest(_ id: String) throws -> (McpRequestRow, McpTokenRecord) {
        _ = try requests.expireOld(now: clock.now)
        guard let request = try requests.get(id: id), let token = try tokens.get(id: request.tokenId) else { throw ApiFailure.notFound }
        guard request.state == .pendingApproval else { throw Self.notPending }
        return (request, token)
    }

    /// A failure is already written on the request by the launch; the operator sees it as the request's state.
    private func run(_ request: McpRequestRow, token: McpTokenRecord, approvedBy: String) async {
        switch request.kind {
        case .create: try? await launchCreate(request, token: token, approvedBy: approvedBy)
        case .delete, .start, .stop: try? await launchAction(request, token: token, approvedBy: approvedBy)
        }
    }
}
