import Foundation
import MSCore

/// What the AI proxy decides without touching the network: which provider address is acceptable, what is sent upstream, and what is read back.
public struct BrainAnswer: Equatable {
    public let text: String
    public let promptTokens: Int
    public let completionTokens: Int
}

public enum BrainRules {
    public static let maxMessageCharacters = 4000
    public static let maxReplyCharacters = 8000
    public static let defaultMaxTokens = 512
    public static let maxTokensRange = 1...4096
    public static let defaultCapabilitySeconds = 600
    public static let capabilitySecondsRange = 60...3600

    /// https to any host, or plain http to this machine or a private network (a local model server). No credentials, query or fragment.
    public static func isAcceptableBaseURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme, let host = url.host, url.user == nil, url.query == nil, url.fragment == nil else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && (host == "localhost" || IPv4.isLoopbackOrPrivate(host))
    }

    public static func completionsURL(base: String) -> URL? {
        URL(string: base.hasSuffix("/") ? base + "chat/completions" : base + "/chat/completions")
    }

    /// The only request the proxy ever makes: one user message, the fixed model, a hard token limit, no streaming.
    public static func upstreamBody(message: String, model: String, maxTokens: Int) throws -> Data {
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "stream": false, "messages": [["role": "user", "content": message]]]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// The first choice's text plus the provider's own token count. Anything else in the reply is ignored.
    public static func parseReply(_ data: Data) -> BrainAnswer? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choice = (object["choices"] as? [[String: Any]])?.first,
              let text = (choice["message"] as? [String: Any])?["content"] as? String, !text.isEmpty else { return nil }
        let usage = object["usage"] as? [String: Any]
        return BrainAnswer(text: String(text.prefix(maxReplyCharacters)), promptTokens: count(usage?["prompt_tokens"]), completionTokens: count(usage?["completion_tokens"]))
    }

    private static func count(_ value: Any?) -> Int {
        guard let number = value as? NSNumber, number.intValue >= 0, number.intValue < 100_000_000 else { return 0 }
        return number.intValue
    }
}
