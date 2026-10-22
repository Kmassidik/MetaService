import Foundation
import MSCore

/// The reason a helper gives for a failed order (for example a VM that did not start). It may hold the last lines the VM printed, so it is cleaned and capped again
/// before it is stored and shown; the panel shows it as text.
public enum HelperFailureText {
    public static let maxLines = 40
    public static let maxBytes = 6000
    private static let errorKey = "error"

    public static func clean(_ text: String) -> String {
        UntrustedText.tail(text, lines: maxLines, maxBytes: maxBytes)
    }

    /// Cleans the `error` entry of a finished order's result, if there is one. The other entries (ids, ports) are left as they are.
    public static func cleanResult(_ result: [String: String]) -> [String: String] {
        var cleaned = result
        cleaned[errorKey] = result[errorKey].map(clean)
        return cleaned
    }
}
