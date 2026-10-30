import Foundation

/// Which scope a call is missing, in words the AI can act on. Pure, so each rule is tested on its own.
public enum McpScopeRules {
    /// Why this scope is missing, or nil when the caller has it.
    public static func missingScope(_ needed: McpScope, has scopes: Set<McpScope>) -> String? {
        guard !scopes.contains(needed) else { return nil }
        return "this token does not have the \"\(needed.rawValue)\" scope: ask the people who run MetaService to add it (Settings, AI access)."
    }

    /// A create that needs more than `create`: the GPU limit needs `gpu`, a shared machine needs `shared`.
    public static func missingCreateScope(gpuMemoryGb: Int?, onSharedMachine: Bool, has scopes: Set<McpScope>) -> String? {
        if gpuMemoryGb != nil, let missing = missingScope(.gpu, has: scopes) { return missing }
        guard onSharedMachine else { return nil }
        return missingScope(.shared, has: scopes)
    }
}
