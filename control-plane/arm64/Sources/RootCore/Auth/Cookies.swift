import Foundation

public enum Cookies {
    /// The value of a cookie that appears exactly once; nil when missing or repeated.
    public static func value(named name: String, header: String?) -> String? {
        let found = (header ?? "").split(separator: ";").compactMap { part -> String? in
            let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return pair.count == 2 && pair[0] == name ? String(pair[1]) : nil
        }
        return found.count == 1 ? found[0] : nil
    }

    public static func set(name: String, value: String, maxAge: Int, secure: Bool, sameSite: String) -> String {
        let flags = secure ? "; Secure" : ""
        return "\(name)=\(value); Path=/; HttpOnly; SameSite=\(sameSite); Max-Age=\(maxAge)\(flags)"
    }
}
