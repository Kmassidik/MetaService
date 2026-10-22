import Foundation
import MSCore

/// The fingerprint of a helper program: the lowercase hex SHA-256 of its file. It is what tells an old helper from a new one when both say the same version.
public enum AgentBuild {
    public static let length = 64
    public static let shortLength = 8
    private static let pattern = #/^[0-9a-f]{64}$/#

    public static func isValid(_ text: String) -> Bool { text.wholeMatch(of: pattern) != nil }

    /// The first characters, which is enough for a person to tell two builds apart.
    public static func short(_ build: String) -> String { String(build.prefix(shortLength)) }

    /// The optional `agent_build` of a helper's facts. A helper that does not say it gives nil; a wrong one is refused.
    static func optional(_ object: StrictObject, _ key: String) throws -> String? {
        guard object.has(key) else { return nil }
        return try object.string(key, pattern: pattern, maxLength: length, minLength: length)
    }
}

/// What the parent can say about replacing one machine's helper: whether a different build is on offer, which one the machine runs and which is the newest.
public struct HelperUpdate: Encodable, Equatable {
    public let available: Bool
    /// The build the machine's helper reported; nil for an older helper that does not say.
    public let currentBuild: String?
    /// The build the parent can put there; nil when the parent has none for that system.
    public let newestBuild: String?
    /// Why there is nothing to offer, in plain words. Nil when there is.
    public let reason: String?

    public init(available: Bool, currentBuild: String?, newestBuild: String?, reason: String?) {
        self.available = available
        self.currentBuild = currentBuild
        self.newestBuild = newestBuild
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey { case available, currentBuild, newestBuild, reason }

    /// Every key is always sent, so the shape never changes.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(available, forKey: .available)
        try box.encode(currentBuild, forKey: .currentBuild)
        try box.encode(newestBuild, forKey: .newestBuild)
        try box.encode(reason, forKey: .reason)
    }
}

public enum HelperUpdateRules {
    public static let noBuildReason = "The parent has no MetaService program for this kind of computer, so its helper cannot be updated from here."
    public static let notReportedReason = "This machine has not reported in yet, so the parent does not know what kind of computer it is."

    /// The name the parent's builds go by: "darwin-arm64", "linux-x86_64", "linux-arm64". Nil when the machine never said what it is.
    public static func system(os: String?, arch: String?) -> String? {
        guard let os, let arch else { return nil }
        let family = os == "macos" ? "darwin" : os
        let chip = arch == "aarch64" ? "arm64" : arch
        return "\(family)-\(chip)"
    }

    /// `builds` maps a system name to the build (SHA-256) of the program the parent has for it.
    public static func decide(os: String?, arch: String?, reported: String?, builds: [String: String]) -> HelperUpdate {
        guard let system = system(os: os, arch: arch) else {
            return HelperUpdate(available: false, currentBuild: reported, newestBuild: nil, reason: notReportedReason)
        }
        guard let newest = builds[system] else {
            return HelperUpdate(available: false, currentBuild: reported, newestBuild: nil, reason: noBuildReason)
        }
        return HelperUpdate(available: reported != newest, currentBuild: reported, newestBuild: newest, reason: nil)
    }
}
