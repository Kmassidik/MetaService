import Foundation

/// The protocol versions the server speaks, the Origin rule, and the shape of a tool result. Pure.
public enum McpProtocol {
    /// Newest first: the answer to a client that asks for something else.
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let newestVersion = supportedVersions[0]
    public static let serverName = "metaservice"
    public static let maxBodyBytes = 64 * 1024
    public static let requestsPerMinute = 60
    public static let createsPerMinute = 10

    /// The client's version when the server speaks it, else the newest.
    public static func negotiate(requested: String?) -> String {
        guard let requested, supportedVersions.contains(requested) else { return newestVersion }
        return requested
    }

    /// `structuredContent` came with 2025-06-18. Dates compare as text.
    public static func supportsStructuredContent(version: String) -> Bool {
        version >= newestVersion
    }

    /// A request without Origin is a normal MCP client. One with Origin is a browser page, and only the panel's own host may send it.
    public static func originAllowed(_ origin: String?, publicURL: String) -> Bool {
        guard let origin else { return true }
        guard let given = URLComponents(string: origin), let wanted = URLComponents(string: publicURL), let host = given.host?.lowercased(), let own = wanted.host?.lowercased() else { return false }
        return host == own && given.port == wanted.port
    }

    /// A tool result: the JSON as pretty text, plus the same object as `structuredContent` when the version allows. `isError` marks a refusal or a failure.
    public static func toolResult(_ object: [String: Any], isError: Bool, version: String) -> [String: Any] {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        var result: [String: Any] = ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]], "isError": isError]
        if supportsStructuredContent(version: version) { result["structuredContent"] = object }
        return result
    }

    /// A refusal the AI can read: one plain sentence.
    public static func failureResult(_ message: String, version: String) -> [String: Any] {
        toolResult(["error": message], isError: true, version: version)
    }
}
