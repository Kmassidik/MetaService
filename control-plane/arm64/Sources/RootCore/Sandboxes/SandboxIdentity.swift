import Foundation

/// Sandbox ids, as `api.yaml` (and `contract/openapi.yaml` for the helper) define them: 20 lowercase letters and digits, so
/// `49983-<id>.<domain>` is a valid host name. The parent picks the id, so a create that is retried can always name what it
/// started and a helper create is idempotent by id.
public enum SandboxIdentity {
    public static let idCharacters = 20
    /// No capitals, no dashes: a host name label may hold both, but a lowercase-only alphabet is what was agreed.
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    public static func newId() -> String {
        String((0..<idCharacters).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    public static func isValid(_ id: String) -> Bool {
        id.count == idCharacters && id.allSatisfy(alphabet.contains)
    }
}
