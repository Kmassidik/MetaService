import Foundation

/// What a token may do. `read` lists and shows, `create` makes and starts and stops its own VMs, `destroy` deletes them,
/// `gpu` allows a GPU memory limit, `shared` reaches machines that joined through Share a PC.
public enum McpScope: String, CaseIterable, Equatable {
    case read, create, destroy, gpu, shared

    /// A new token without a choice gets these two.
    public static let defaults: Set<McpScope> = [.read, .create]

    /// The scopes named in a list of texts. An empty list, an unknown name or a repeat is refused with the allowed names.
    public static func parse(_ names: [String]) throws -> Set<McpScope> {
        guard !names.isEmpty else { throw InputError("scopes needs at least one of: \(allNames)") }
        let scopes = try names.map { name -> McpScope in
            guard let scope = McpScope(rawValue: name) else { throw InputError("unknown scope \"\(name)\"; the scopes are: \(allNames)") }
            return scope
        }
        guard Set(scopes).count == scopes.count else { throw InputError("scopes lists a scope twice") }
        return Set(scopes)
    }

    /// In the order above, so a stored list never changes shape.
    public static func names(_ scopes: Set<McpScope>) -> [String] {
        allCases.filter(scopes.contains).map(\.rawValue)
    }

    private static var allNames: String { allCases.map(\.rawValue).joined(separator: ", ") }
}
