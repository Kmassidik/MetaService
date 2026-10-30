import Foundation

/// The body of the panel's "Create token": a name, and optionally scopes, quotas, a lifetime and auto_approve. Strict: unknown fields and bad numbers are refused.
public struct McpTokenRequest: Equatable {
    public static let maxNameCharacters = 40
    public static let expiryDays = 1...365
    static let namePattern = #/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$/#
    static let scopePattern = #/^[a-z]{1,16}$/#
    static let fields: Set<String> = ["name", "scopes", "quotas", "expires_in_days", "auto_approve"]

    public let name: String
    public let scopes: Set<McpScope>
    public let quotas: McpQuotas
    public let expiresInDays: Int
    public let autoApprove: Bool

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: Self.fields)
        guard object.has("name") else { throw InputError("name is required") }
        name = try object.string("name", pattern: Self.namePattern, maxLength: Self.maxNameCharacters, minLength: 1)
        scopes = object.has("scopes") ? try McpScope.parse(try object.strings("scopes", maxCount: McpScope.allCases.count, pattern: Self.scopePattern, maxLength: 16)) : McpScope.defaults
        quotas = object.has("quotas") ? try McpQuotas(object: try object.object("quotas", allowed: McpQuotas.keys)) : McpQuotas.defaults
        expiresInDays = object.has("expires_in_days") ? try object.int("expires_in_days", range: Self.expiryDays) : 90
        autoApprove = object.has("auto_approve") ? try object.bool("auto_approve") : false
    }
}
