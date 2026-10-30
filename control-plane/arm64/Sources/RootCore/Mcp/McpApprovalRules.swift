import Foundation

/// What a call needs before it runs: a scope the token has, and sometimes a person's yes. Pure, so each rule is tested on its own.
public enum McpApprovalRules {
    /// What a create asks for, as far as the approval rules care.
    public struct CreateShape: Equatable {
        public let size: McpSize
        public let dimensions: McpSize.Dimensions
        public let gpuMemoryGb: Int?
        public let onSharedMachine: Bool

        public init(size: McpSize, dimensions: McpSize.Dimensions, gpuMemoryGb: Int?, onSharedMachine: Bool) {
            self.size = size
            self.dimensions = dimensions
            self.gpuMemoryGb = gpuMemoryGb
            self.onSharedMachine = onSharedMachine
        }
    }

    /// Why a person must approve this create, or nil when it can run at once. A token with `auto_approve` never waits.
    public static func reason(forCreate shape: CreateShape, autoApprove: Bool) -> String? {
        guard !autoApprove else { return nil }
        if shape.gpuMemoryGb != nil { return "it asks for a GPU memory limit" }
        if shape.size == .large { return "it asks for the large size" }
        if shape.size == .custom && McpSize.exceedsMedium(shape.dimensions) { return "its custom size is above the medium size" }
        if shape.onSharedMachine { return "it runs on a shared machine" }
        return nil
    }

    /// A delete always waits for a person, unless the token has `auto_approve`.
    public static func reason(forDelete autoApprove: Bool) -> String? {
        autoApprove ? nil : "deleting a VM is permanent"
    }

    /// Why this scope is missing, in words the AI can act on. Nil when the token has it.
    public static func missingScope(_ needed: McpScope, has scopes: Set<McpScope>) -> String? {
        guard !scopes.contains(needed) else { return nil }
        return "this token does not have the \"\(needed.rawValue)\" scope: ask a person to add it in the panel (Settings, AI access)."
    }

    /// A create that needs more than its scopes: the GPU limit needs `gpu`, a shared machine needs `shared`.
    public static func missingCreateScope(gpuMemoryGb: Int?, onSharedMachine: Bool, has scopes: Set<McpScope>) -> String? {
        if gpuMemoryGb != nil, let missing = missingScope(.gpu, has: scopes) { return missing }
        guard onSharedMachine else { return nil }
        return missingScope(.shared, has: scopes)
    }
}
