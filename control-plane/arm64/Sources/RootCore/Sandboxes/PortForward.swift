import Foundation

/// One request on its way into a sandbox, as the helper's port route (`/v1/sandboxes/{id}/ports/{port}/{path}`) takes it.
/// Pure, so the query rule is tested without a socket: the path is passed on unchanged and our own token is taken out of the
/// query before the helper ever sees it.
public enum PortForward {
    private static let prefix = "/v1/sandboxes"
    /// The separators a query is written with, and the parameter name this parent owns.
    private static let separator: Character = "&"
    private static let equals: Character = "="
    private static let tokenName = PortToken.queryName

    /// The helper's path for one forwarded request. `path` is the request's own path as it arrived (`/`, `/a/b`), so the
    /// program inside sees the URL it was given, not one the parent rebuilt.
    public static func path(sandbox: String, port: Int, path: String, query: String?) -> String {
        let forwarded = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let rest = forwarded.isEmpty ? "" : forwarded
        return "\(prefix)/\(sandbox)/ports/\(port)/\(rest)" + queryPart(query)
    }

    /// The query as it arrived, minus our token parameter, or nil when nothing is left. Order and encoding are kept, so a
    /// program's own parameters reach it exactly as the caller wrote them.
    public static func queryWithoutToken(_ query: String?) -> String? {
        guard let query else { return nil }
        let kept = query.split(separator: separator, omittingEmptySubsequences: true).filter { pair in
            let parts = pair.split(separator: equals, maxSplits: 1, omittingEmptySubsequences: false)
            return parts.first != Substring(tokenName)
        }
        return kept.isEmpty ? nil : kept.joined(separator: String(separator))
    }

    private static func queryPart(_ query: String?) -> String {
        queryWithoutToken(query).map { "?" + $0 } ?? ""
    }
}
