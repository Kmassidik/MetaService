import Foundation

/// The public name of one exposed port: `https://<label>.<domain>`, where the label is 16 characters of lowercase base32
/// over the first 80 bits of the Root's own signature for (sandbox, port). See `sandbox/README.md`, "Addresses": a port in a
/// public name advertises what is listening, and a name is not authentication, so the name is opaque and the token
/// (`PortToken`) is what proves the caller was sent it.
///
/// Nothing is stored to make a label: the same sandbox and port always give the same one, and the row in `sandbox_ports` is
/// what maps a label back to its (sandbox, port). The signature is passed in, so this file needs no key and stays pure.
public enum PortHosts {
    /// The purpose the label's signature is derived under, so it can never collide with another signature the Root makes.
    public static let purpose = "sandbox-port-label"
    /// `a-z` and `2-7`: RFC 4648's base32 alphabet in lowercase, which is also a valid host-name label.
    public static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
    public static let labelCharacters = 16
    /// Five bits a character, so sixteen characters carry exactly 80 bits: not enumerable by scanning.
    private static let bitsPerCharacter = 5
    private static let bitsPerHexCharacter = 4
    /// Hex characters of the signature that hold those 80 bits.
    private static let signatureCharacters = labelCharacters * bitsPerCharacter / bitsPerHexCharacter
    private static let hexCharacters = Set("0123456789abcdef")

    /// What the Root signs: the sandbox and the port, so one sandbox's ports never share a label.
    public static func subject(sandbox: String, port: Int) -> String {
        "\(sandbox):\(port)"
    }

    public static func isLabel(_ text: String) -> Bool {
        text.count == labelCharacters && text.allSatisfy(alphabet.contains)
    }

    /// The label for one signature (the Root's `SecretBox.signature(subject:purpose:)` output), or nil when the signature is
    /// not the lowercase hex this expects.
    public static func label(from signature: String) -> String? {
        guard let bits = bits(of: signature), bits.count >= labelCharacters * bitsPerCharacter else { return nil }
        return stride(from: 0, to: labelCharacters * bitsPerCharacter, by: bitsPerCharacter).map { start in
            alphabet[value(of: bits[start..<start + bitsPerCharacter])]
        }.reduce(into: "") { $0.append($1) }
    }

    /// The host a program fetches: the label and the sandbox domain, one level, as Cloudflare's free certificate covers.
    public static func host(label: String, domain: String) -> String {
        "\(label).\(domain.lowercased())"
    }

    /// The label when a `Host` header names one of our ports (`<label>.<domain>`, with an optional port number), and nil
    /// otherwise. Nothing else is a port host: the panel's name and the API's name are not labels.
    public static func label(inHost host: String?, domain: String) -> String? {
        guard let host else { return nil }
        let name = String(host.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? "").lowercased()
        let suffix = "." + domain.lowercased()
        guard name.count == labelCharacters + suffix.count, name.hasSuffix(suffix) else { return nil }
        let label = String(name.dropLast(suffix.count))
        return isLabel(label) ? label : nil
    }

    /// The signature's bits, most significant first, or nil when it is not lowercase hex.
    private static func bits(of signature: String) -> [UInt8]? {
        var bits: [UInt8] = []
        for character in signature.prefix(signatureCharacters) {
            guard let nibble = character.hexDigitValue, hexCharacters.contains(character) else { return nil }
            for shift in stride(from: bitsPerHexCharacter - 1, through: 0, by: -1) {
                bits.append(UInt8((nibble >> shift) & 1))
            }
        }
        return bits
    }

    private static func value(of bits: ArraySlice<UInt8>) -> Int {
        bits.reduce(0) { ($0 << 1) | Int($1) }
    }
}
