import Foundation

/// JSON-RPC 2.0 as MCP uses it over HTTP: one message per request. Parsing and the shapes of the replies, with no I/O.
public enum McpRpcCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

/// The id a client chose. Echoed back exactly as sent.
public enum McpRpcId: Equatable {
    case number(Int)
    case text(String)
    case none

    var json: Any {
        switch self {
        case .number(let number): return number
        case .text(let text): return text
        case .none: return NSNull()
        }
    }
}

public struct McpRpcCall: Equatable {
    public let id: McpRpcId
    public let method: String
    /// The `params` object, re-encoded so it can be read strictly. Empty `{}` when the client sent none.
    public let params: Data
}

public enum McpRpcMessage: Equatable {
    /// Has an id: gets a JSON reply.
    case request(McpRpcCall)
    /// Has no id: gets 202 and nothing else.
    case notification(method: String)
    /// Could not be read: gets this JSON-RPC error (id none when the id could not be read either).
    case invalid(id: McpRpcId, code: Int, message: String)
}

public enum McpJsonRpc {
    public static func parse(_ body: Data) -> McpRpcMessage {
        guard let parsed = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) else {
            return .invalid(id: .none, code: McpRpcCode.parseError, message: "the body is not valid JSON")
        }
        if parsed is [Any] {
            return .invalid(id: .none, code: McpRpcCode.invalidRequest, message: "batches are not supported: send one message per request")
        }
        guard let object = parsed as? [String: Any] else {
            return .invalid(id: .none, code: McpRpcCode.invalidRequest, message: "the message must be a JSON object")
        }
        return read(object)
    }

    private static func read(_ object: [String: Any]) -> McpRpcMessage {
        let id = readId(object["id"])
        guard object["jsonrpc"] as? String == "2.0" else { return invalid(id, "jsonrpc must be \"2.0\"") }
        guard let method = object["method"] as? String, !method.isEmpty else { return invalid(id, "method must be a text") }
        guard let params = readParams(object["params"]) else {
            return .invalid(id: id ?? .none, code: McpRpcCode.invalidParams, message: "params must be an object")
        }
        guard object["id"] != nil else { return .notification(method: method) }
        guard let id else { return invalid(nil, "id must be a whole number or a text") }
        return .request(McpRpcCall(id: id, method: method, params: params))
    }

    private static func invalid(_ id: McpRpcId?, _ message: String) -> McpRpcMessage {
        .invalid(id: id ?? .none, code: McpRpcCode.invalidRequest, message: message)
    }

    /// Nil when the client sent an id of another kind (a boolean, null, a list, a fraction).
    private static func readId(_ value: Any?) -> McpRpcId? {
        if let text = value as? String { return .text(text) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == number.doubleValue.rounded(), abs(number.doubleValue) < 9e15 else { return nil }
        return .number(number.intValue)
    }

    private static func readParams(_ value: Any?) -> Data? {
        guard let value, !(value is NSNull) else { return Data("{}".utf8) }
        guard let object = value as? [String: Any] else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    // MARK: replies

    public static func result(id: McpRpcId, _ result: [String: Any]) -> Data {
        encode(["jsonrpc": "2.0", "id": id.json, "result": result])
    }

    public static func error(id: McpRpcId, code: Int, message: String) -> Data {
        encode(["jsonrpc": "2.0", "id": id.json, "error": ["code": code, "message": message]])
    }

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
