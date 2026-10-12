import Foundation

public enum Shell {
    /// `text` as one word for `sh`: inside single quotes, with each single quote written as '\''. Safe for any text without a NUL byte.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
