import Foundation
import MSCore

/// The program a machine makes VMs with, as its helper reports it (contract 1.3.0). `version` is nil when the helper could not tell: it is never guessed.
public struct EngineReport: Equatable, Codable {
    public let name: String
    public let version: String?
    public let ready: Bool

    static let keys: Set<String> = ["name", "version", "ready"]
    private static let namePattern = #/^[a-z0-9][a-z0-9-]{0,31}$/#

    public init(name: String, version: String?, ready: Bool) {
        self.name = name
        self.version = version
        self.ready = ready
    }

    init(_ object: StrictObject) throws {
        name = try object.string("name", pattern: Self.namePattern, maxLength: 32, minLength: 1)
        version = try ReportedVersion.optional(object, "version")
        ready = try object.bool("ready")
    }

    enum CodingKeys: String, CodingKey { case name, version, ready }

    /// A missing version is sent as null, so the shape never changes.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(name, forKey: .name)
        try box.encode(version, forKey: .version)
        try box.encode(ready, forKey: .ready)
    }
}

/// A version text a helper or an engine reports about itself. Not always 1.2.3 (the pretend helper says fake-1), so the rule is only "short and plain".
enum ReportedVersion {
    static let maxLength = 32
    private static let pattern = #/^[A-Za-z0-9][A-Za-z0-9._+-]{0,31}$/#

    static func optional(_ object: StrictObject, _ key: String) throws -> String? {
        guard object.has(key) else { return nil }
        return try object.string(key, pattern: pattern, maxLength: maxLength, minLength: 1)
    }
}
