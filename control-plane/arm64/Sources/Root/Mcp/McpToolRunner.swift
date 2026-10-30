import Foundation
import RootCore
import RootStore

/// One `tools/call`: the scope check, the strict reading of the arguments, the tool itself, and the audit row. Every outcome is a tool result; nothing here throws to the transport.
extension McpService {
    func callTool(_ tool: McpTool, arguments: Data, token: McpTokenRecord, version: String) async -> [String: Any] {
        if let missing = McpApprovalRules.missingScope(tool.scope, has: token.scopes) {
            record(token, tool: tool.rawValue, status: "refused", target: nil, detail: ["kind": "scope"])
            return McpProtocol.failureResult(missing, version: version)
        }
        do {
            let reply = try await run(tool, arguments: arguments, token: token)
            record(token, tool: tool.rawValue, status: reply.status, target: reply.target, detail: reply.detail)
            return McpProtocol.toolResult(reply.payload, isError: false, version: version)
        } catch {
            let refusal = McpRefusal.from(error)
            record(token, tool: tool.rawValue, status: refusal.kind == "failed" ? "failed" : "refused", target: nil, detail: ["kind": refusal.kind])
            return McpProtocol.failureResult(refusal.message, version: version)
        }
    }

    private func run(_ tool: McpTool, arguments: Data, token: McpTokenRecord) async throws -> McpToolReply {
        switch tool {
        case .listMachines:
            try McpLookupInput.none(arguments: arguments)
            return McpToolReply(payload: try listMachines(token: token))
        case .machineCapacity:
            let input = try McpLookupInput.capacity(arguments: arguments)
            return McpToolReply(payload: try machineCapacity(input.machine ?? "", token: token), target: input.machine)
        case .listVms:
            settle(token)
            let input = try McpLookupInput.vms(arguments: arguments)
            return McpToolReply(payload: try listVms(machine: input.machine, token: token), target: input.machine)
        case .vmStatus:
            settle(token)
            let input = try McpVmInput(arguments: arguments, withWait: false)
            return McpToolReply(payload: try vmStatus(machine: input.machine, vm: input.vm, token: token), target: "\(input.machine)/\(input.vm)")
        case .getRequest:
            settle(token)
            let input = try McpLookupInput.request(arguments: arguments)
            return McpToolReply(payload: try getRequest(input.requestId ?? "", token: token), detail: ["request": input.requestId ?? ""])
        case .createVm: return try await createVm(try McpCreateVmInput(arguments: arguments), token: token)
        case .startVm: return try await startVm(try McpVmInput(arguments: arguments, withWait: true), token: token)
        case .stopVm: return try await stopVm(try McpVmInput(arguments: arguments, withWait: true), token: token)
        case .deleteVm: return try await deleteVm(try McpVmInput(arguments: arguments, withWait: false), token: token)
        }
    }
}
