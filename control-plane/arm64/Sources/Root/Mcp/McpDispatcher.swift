import Foundation
import RootCore

/// What a client asked, answered the way MCP wants: `initialize`, `ping`, `tools/list` and `tools/call`. Anything else is -32601.
extension McpService {
    /// Newer clients send this header on every request after `initialize`. Without it the older rules apply (no structured content).
    static let fallbackVersion = "2025-03-26"

    /// The JSON reply for one request. A tool that fails is still a result (`isError`); only a request that cannot be read is a JSON-RPC error.
    func dispatch(_ call: McpRpcCall, token: McpTokenRecord, headerVersion: String?) async -> Data {
        switch call.method {
        case "initialize": return initialize(call)
        case "ping": return McpJsonRpc.result(id: call.id, [:])
        case "tools/list": return McpJsonRpc.result(id: call.id, ["tools": Self.toolList])
        case "tools/call": return await toolsCall(call, token: token, version: headerVersion.map { McpProtocol.negotiate(requested: $0) } ?? Self.fallbackVersion)
        default: return McpJsonRpc.error(id: call.id, code: McpRpcCode.methodNotFound, message: "unknown method \"\(call.method.prefix(64))\"")
        }
    }

    private func initialize(_ call: McpRpcCall) -> Data {
        let requested = (try? JSONSerialization.jsonObject(with: call.params) as? [String: Any])?["protocolVersion"] as? String
        let result: [String: Any] = ["protocolVersion": McpProtocol.negotiate(requested: requested), "capabilities": ["tools": [String: Any]()],
                                     "serverInfo": ["name": McpProtocol.serverName, "version": "1.0.0"]]
        return McpJsonRpc.result(id: call.id, result)
    }

    static var toolList: [[String: Any]] {
        McpTool.allCases.map { ["name": $0.rawValue, "description": $0.description, "inputSchema": McpToolSchemas.input(of: $0)] }
    }

    private func toolsCall(_ call: McpRpcCall, token: McpTokenRecord, version: String) async -> Data {
        let params = (try? JSONSerialization.jsonObject(with: call.params)) as? [String: Any] ?? [:]
        guard let name = params["name"] as? String, let tool = McpTool(rawValue: name) else {
            return McpJsonRpc.error(id: call.id, code: McpRpcCode.invalidParams, message: "name must be one of: \(McpTool.names.joined(separator: ", "))")
        }
        guard let arguments = Self.argumentsData(params["arguments"]) else {
            return McpJsonRpc.error(id: call.id, code: McpRpcCode.invalidParams, message: "arguments must be an object")
        }
        return McpJsonRpc.result(id: call.id, await callTool(tool, arguments: arguments, token: token, version: version))
    }

    private static func argumentsData(_ value: Any?) -> Data? {
        guard let value, !(value is NSNull) else { return Data("{}".utf8) }
        guard let object = value as? [String: Any] else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }
}
