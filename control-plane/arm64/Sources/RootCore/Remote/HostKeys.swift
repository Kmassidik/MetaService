import CryptoKit
import Foundation

/// The SSH host key of a computer, as the operator sees and confirms it before the first login. Pure text handling: the programs that
/// fetch the key (ssh-keyscan, ssh-keygen) are run by the Root.
public enum HostKeys {
    private static let fingerprint = try! NSRegularExpression(pattern: "^SHA256:[A-Za-z0-9+/]{43}$")
    private static let keyTypes = ["ssh-ed25519", "ecdsa-sha2-nistp256", "ssh-rsa"]

    public static func isFingerprint(_ text: String) -> Bool {
        fingerprint.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The fingerprint from the answer of `ssh-keygen -lf -`: "256 SHA256:abc... host (ED25519)".
    public static func parseFingerprint(keygenOutput: String) -> String? {
        for line in keygenOutput.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            if parts.count >= 2, isFingerprint(String(parts[1])) { return String(parts[1]) }
        }
        return nil
    }

    /// The fingerprint of a key line from ssh-keyscan, worked out here (SHA-256 of the key, in base64 without padding) so no program has to be trusted to say it.
    public static func fingerprint(ofKeyLine line: String) -> String? {
        let parts = line.split(separator: " ")
        guard parts.count == 3, let blob = Data(base64Encoded: String(parts[2])) else { return nil }
        return "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    /// How ssh-keyscan and known_hosts name a computer: the host alone on port 22, "[host]:port" on any other.
    public static func spec(host: String, port: Int) -> String { port == 22 ? host : "[\(host)]:\(port)" }

    /// The one key line to trust from the answer of ssh-keyscan: ed25519 first, then ecdsa, then rsa. Comment lines and odd lines are ignored.
    public static func chooseKey(scanOutput: String) -> String? {
        let lines = scanOutput.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.hasPrefix("#") }
        for type in keyTypes {
            if let line = lines.first(where: { isKeyLine($0, type: type) }) { return line }
        }
        return nil
    }

    private static func isKeyLine(_ line: String, type: String) -> Bool {
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[1] == type else { return false }
        let encoded = parts[2].allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
        return encoded && !parts[0].hasPrefix("-")
    }
}
