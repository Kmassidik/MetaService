import Foundation

/// What a create asks for, after every field of E2B's body has been looked at: the supported ones kept, the unsupported ones
/// refused. Nothing is silently dropped, so a program never gets weaker rules than it asked for (see `sandbox/api.yaml`).
public struct SandboxCreateSpec: Equatable, Sendable {
    public let template: String
    public let timeoutSeconds: Int
    public let envVars: [String: String]

    public init(template: String, timeoutSeconds: Int, envVars: [String: String]) {
        self.template = template
        self.timeoutSeconds = timeoutSeconds
        self.envVars = envVars
    }
}

/// Reads `POST /v2/sandboxes`. The body is taken as a dictionary first, so a field we do not know is refused by name instead
/// of being ignored by a decoder.
public enum SandboxApiCreateBody {
    public static let defaultTimeoutSeconds = SandboxEndTime.defaultTimeoutSeconds
    public static let maxMetadataPairs = 50
    public static let maxMetadataKeyCharacters = 64
    public static let maxEnvVars = 100
    public static let maxEnvValueCharacters = 16_384
    public static let templateCharacters = 1...63

    private static let fields: Set<String> = [
        "templateID", "timeout", "autoPause", "autoPauseMemory", "autoResume", "allow_internet_access",
        "metadata", "envVars", "network", "iam", "mcp", "volumeMounts",
    ]
    private static let envKeyPattern = "^[A-Za-z_][A-Za-z0-9_]{0,127}$"

    public static func parse(_ body: Data) throws -> SandboxCreateSpec {
        guard let json = try? JSONSerialization.jsonObject(with: body), let object = json as? [String: Any] else {
            throw SandboxApiFailure.invalid("The body must be a JSON object.")
        }
        return try parse(object)
    }

    public static func parse(_ object: [String: Any]) throws -> SandboxCreateSpec {
        try refuseUnknownFields(object)
        let template = try templateID(object["templateID"])
        try refuseUnsupported(object)
        try checkMetadata(object["metadata"])
        let envVars = try environment(object["envVars"])
        let timeout = try timeoutSeconds(object["timeout"])
        return SandboxCreateSpec(template: template, timeoutSeconds: timeout, envVars: envVars)
    }

    // MARK: the fields

    private static func refuseUnknownFields(_ object: [String: Any]) throws {
        if let unknown = object.keys.first(where: { !fields.contains($0) }) {
            throw SandboxApiFailure.invalid("Unknown field \(unknown).")
        }
    }

    /// Everything E2B sends that v1 does not do yet. Each refusal names the field, and says what would be accepted.
    private static func refuseUnsupported(_ object: [String: Any]) throws {
        guard object["autoPause"].map(isFalse) ?? true else {
            throw SandboxApiFailure.unsupported("autoPause is not supported yet: a sandbox always ends at its timeout.")
        }
        guard object["autoPauseMemory"].map(isTrueOrAbsent) ?? true else {
            throw SandboxApiFailure.unsupported("autoPauseMemory false is not supported: a pause always keeps memory, and pausing is not available yet.")
        }
        try refuseAutoResume(object["autoResume"])
        guard object["allow_internet_access"].map(isFalse) ?? true else {
            throw SandboxApiFailure.unsupported("Internet access is not available to sandboxes yet; allow_internet_access must be false or absent.")
        }
        try refuseNetwork(object["network"])
        try refuseNullOnly(object["iam"], named: "iam")
        try refuseNullOnly(object["mcp"], named: "mcp")
        guard object["volumeMounts"].map(isEmptyList) ?? true else {
            throw SandboxApiFailure.unsupported("Volumes are not supported yet: volumeMounts must be empty or absent.")
        }
    }

    private static func refuseAutoResume(_ value: Any?) throws {
        guard let value, !(value is NSNull) else { return }
        guard let object = value as? [String: Any], object.keys.allSatisfy({ $0 == "enabled" }), object["enabled"].map(isFalse) ?? true else {
            throw SandboxApiFailure.unsupported("autoResume is not supported yet: traffic does not wake a paused sandbox.")
        }
    }

    /// E2B's finer network rules. Public ports are open anyway, so only that one flag is accepted.
    private static func refuseNetwork(_ value: Any?) throws {
        guard let value, !(value is NSNull) else { return }
        guard let object = value as? [String: Any], object.keys.allSatisfy({ $0 == "allowPublicTraffic" }),
              object["allowPublicTraffic"].map(isTrue) ?? true else {
            throw SandboxApiFailure.unsupported("Network rules are not supported yet; network must be absent, null, empty, or only allowPublicTraffic true.")
        }
    }

    private static func refuseNullOnly(_ value: Any?, named name: String) throws {
        guard let value, !(value is NSNull) else { return }
        throw SandboxApiFailure.unsupported("\(name) is not supported yet; it must be absent or null.")
    }

    /// The program's own labels are not kept by the parent yet (the record has no place for them), so they are refused
    /// rather than accepted and lost.
    private static func checkMetadata(_ value: Any?) throws {
        guard let value, !(value is NSNull) else { return }
        guard let object = value as? [String: Any] else { throw SandboxApiFailure.invalid("metadata must be an object of strings.") }
        guard !object.isEmpty else { return }
        throw SandboxApiFailure.unsupported("metadata is not kept yet; send it empty or leave it out.")
    }

    private static func environment(_ value: Any?) throws -> [String: String] {
        guard let value, !(value is NSNull) else { return [:] }
        guard let object = value as? [String: Any] else { throw SandboxApiFailure.invalid("envVars must be an object of strings.") }
        guard object.count <= maxEnvVars else { throw SandboxApiFailure.invalid("envVars holds at most \(maxEnvVars) entries.") }
        var result: [String: String] = [:]
        for (key, raw) in object {
            guard key.range(of: envKeyPattern, options: .regularExpression) != nil else {
                throw SandboxApiFailure.invalid("envVars key \(key) must match \(envKeyPattern).")
            }
            guard let text = raw as? String, text.count <= maxEnvValueCharacters else {
                throw SandboxApiFailure.invalid("envVars value for \(key) must be a string of at most \(maxEnvValueCharacters) characters.")
            }
            result[key] = text
        }
        return result
    }

    private static func templateID(_ value: Any?) throws -> String {
        guard let text = value as? String else { throw SandboxApiFailure.invalid("templateID is required.") }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard text.count <= templateCharacters.upperBound, let first = text.first, first != "-",
              text.unicodeScalars.allSatisfy(allowed.contains) else {
            throw SandboxApiFailure.invalid("templateID must be lowercase letters, digits and dashes, and not start with a dash.")
        }
        return text
    }

    /// E2B's SDK always sends it (its own default is 300); a plain HTTP caller may leave it out.
    private static func timeoutSeconds(_ value: Any?) throws -> Int {
        guard let value, !(value is NSNull) else { return defaultTimeoutSeconds }
        guard let number = value as? NSNumber, number.doubleValue == number.doubleValue.rounded(), let timeout = Int(exactly: number) else {
            throw SandboxApiFailure.invalid("timeout must be a whole number of seconds.")
        }
        guard timeout >= SandboxEndTime.minimumTimeoutSeconds else {
            throw SandboxApiFailure.invalid("timeout must be at least \(SandboxEndTime.minimumTimeoutSeconds) second.")
        }
        return timeout
    }

    // MARK: small JSON checks

    private static func isFalse(_ value: Any) -> Bool { (value as? NSNumber)?.boolValue == false }
    private static func isTrue(_ value: Any) -> Bool { (value as? NSNumber)?.boolValue == true }
    private static func isTrueOrAbsent(_ value: Any) -> Bool { (value as? NSNumber)?.boolValue != false }
    private static func isEmptyList(_ value: Any) -> Bool { (value as? [Any])?.isEmpty == true }
}
