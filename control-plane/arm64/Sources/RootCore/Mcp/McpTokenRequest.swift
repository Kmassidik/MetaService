import Foundation

/// The name rule shared by people and tokens: it shows up in the panel and in the audit trail (`mcp:<person>`), so it is plain text.
enum McpNames {
    static let maxCharacters = 40
    static let pattern = #/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$/#
    static let scopePattern = #/^[a-z]{1,16}$/#

    static func read(_ object: StrictObject) throws -> String {
        guard object.has("name") else { throw InputError("name is required") }
        return try object.string("name", pattern: pattern, maxLength: maxCharacters, minLength: 1)
    }

    static func scopes(_ object: StrictObject) throws -> Set<McpScope> {
        try McpScope.parse(try object.strings("scopes", maxCount: McpScope.allCases.count, pattern: scopePattern, maxLength: 16))
    }
}

/// The body of the panel's "Create token": a name, the person it belongs to, and optionally scopes and a lifetime. Quotas are the person's, not the token's.
/// The scopes must be a subset of the person's: that is checked where the person is known.
public struct McpTokenRequest: Equatable {
    public static let expiryDays = 1...365
    public static let defaultExpiryDays = 90
    static let personPattern = #/^[a-z0-9][a-z0-9-]{0,62}$/#
    static let fields: Set<String> = ["name", "person_id", "scopes", "expires_in_days"]

    public let name: String
    public let personId: String
    /// Nil: the person's own scopes.
    public let scopes: Set<McpScope>?
    public let expiresInDays: Int

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: Self.fields)
        name = try McpNames.read(object)
        guard object.has("person_id") else { throw InputError("person_id is required: choose which person the token is for") }
        personId = try object.string("person_id", pattern: Self.personPattern, maxLength: 63, minLength: 1)
        scopes = object.has("scopes") ? try McpNames.scopes(object) : nil
        expiresInDays = object.has("expires_in_days") ? try object.int("expires_in_days", range: Self.expiryDays) : Self.defaultExpiryDays
    }
}

/// Add a person (name, scopes, quotas) or change one (scopes and quotas only: a name is for good, so the audit trail stays readable).
public struct McpPersonRequest: Equatable {
    static let createFields: Set<String> = ["name", "scopes", "quotas"]
    static let changeFields: Set<String> = ["scopes", "quotas"]

    public let name: String?
    public let scopes: Set<McpScope>?
    public let quotas: McpQuotas?

    /// A new person: only the name is needed. Scopes default to read and create, quotas to the defaults.
    public static func creating(body: Data) throws -> McpPersonRequest {
        let object = try StrictObject(data: body, allowed: createFields)
        return McpPersonRequest(name: try McpNames.read(object), scopes: try optionalScopes(object) ?? McpScope.defaults, quotas: try optionalQuotas(object) ?? McpQuotas.defaults)
    }

    /// A change: what is not named stays as it is. Nothing named is refused.
    public static func changing(body: Data) throws -> McpPersonRequest {
        let object = try StrictObject(data: body, allowed: changeFields)
        let change = McpPersonRequest(name: nil, scopes: try optionalScopes(object), quotas: try optionalQuotas(object))
        guard change.scopes != nil || change.quotas != nil else { throw InputError("name the scopes or the quotas to change") }
        return change
    }

    private static func optionalScopes(_ object: StrictObject) throws -> Set<McpScope>? {
        object.has("scopes") ? try McpNames.scopes(object) : nil
    }

    private static func optionalQuotas(_ object: StrictObject) throws -> McpQuotas? {
        object.has("quotas") ? try McpQuotas(object: try object.object("quotas", allowed: McpQuotas.keys)) : nil
    }
}
