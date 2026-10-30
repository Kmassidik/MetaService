import Foundation

/// What a tool call came to, for the reply and for the audit row. A refusal or failure is thrown as `McpRefusal` instead.
struct McpToolReply {
    var payload: [String: Any]
    /// `ok`, `needs_approval` or `approved`: the word in the audit row.
    var status = "ok"
    var target: String?
    var detail: [String: String] = [:]
}
