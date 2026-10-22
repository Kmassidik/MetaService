import Foundation
import MSCore

/// The list of SSH public keys for one VM's root account, checked before anything is sent into the VM. The Root checks the same rules; this is the second check.
/// Where it lives: macOS helper, `Sources/AgentCore/SshKeys/`. The Linux helper has the same rules in `agent/linux/src/ssh_keys.rs`.
public enum SshKeyLines {
    public static let maxKeys = 20
    public static let maxLineLength = 800

    /// A key type, one space, base64, and an optional comment of up to 64 characters. Nothing may come before the key type, so no `command=` or other option can be smuggled in.
    private static let linePattern = #/(?:ssh-ed25519|ecdsa-sha2-nistp(?:256|384|521)|ssh-rsa|sk-ssh-ed25519@openssh\.com) [A-Za-z0-9+\/]+={0,3}(?: [A-Za-z0-9._@+:-]{1,64})?/#

    /// Refuses the whole list when it is too long or any line is not one plain public key. The message names the position, never the key.
    public static func validate(_ keys: [String]) throws {
        guard keys.count <= maxKeys else { throw InputError("keys has too many items (at most \(maxKeys))") }
        for (index, key) in keys.enumerated() where !isValid(key) {
            throw InputError("keys/\(index) is not a valid single-line SSH public key")
        }
    }

    public static func isValid(_ key: String) -> Bool {
        key.utf8.count <= maxLineLength && key.wholeMatch(of: linePattern) != nil
    }

    /// What goes on the VM's standard input: every key on its own line, a newline after the last one, and nothing at all for an empty list.
    public static func fileContent(_ keys: [String]) -> Data {
        Data(keys.map { $0 + "\n" }.joined().utf8)
    }
}

/// The body of `PUT /v1/workloads/{id}/ssh-keys`.
public struct SshKeysRequest: Equatable {
    public let keys: [String]

    private static let anyText = #/[\s\S]*/#

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["keys"])
        keys = try object.strings("keys", maxCount: SshKeyLines.maxKeys, pattern: Self.anyText, maxLength: SshKeyLines.maxLineLength)
        try SshKeyLines.validate(keys)
    }
}
