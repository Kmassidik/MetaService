import Foundation

/// The name a computer gives itself on the local network (mDNS), read from the answer of `dig -x <ip> @224.0.0.251 -p 5353 +short`: a line like `Mac-Studio.local.`.
/// Anything that is not a plain name (spaces, escapes, markup) is not used, so a computer can never put odd text into the page.
public enum MdnsName {
    private static let suffix = ".local."
    private static let plainName = try! Regex(#"^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$"#)

    public static func parse(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasSuffix(suffix) else { continue }
            let name = String(text.dropLast(suffix.count))
            if name.wholeMatch(of: plainName) != nil { return name }
        }
        return nil
    }
}
