import Foundation

/// The one id/name shape used everywhere (machines, workloads, commands). Same pattern as contract/openapi.yaml.
public enum Ids {
    private static let pattern = try! Regex("^[a-z0-9][a-z0-9-]{0,62}$")
    private static let semver = try! Regex("^[0-9]+\\.[0-9]+\\.[0-9]+$")

    public static func isValid(_ text: String) -> Bool {
        text.wholeMatch(of: pattern) != nil
    }

    public static func isSemver(_ text: String) -> Bool {
        text.wholeMatch(of: semver) != nil
    }
}
