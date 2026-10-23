import Foundation
import MSCore

/// The optional `cpu_model` of a helper's facts: the name of the machine's CPU as the system reports it.
/// It comes from the machine, so it is cleaned before it is kept: control characters go, runs of spaces become one, and the rest is cut to a size.
public enum CpuModelText {
    public static let maxLength = 120
    /// More than this is a broken helper, not a long name: refused rather than cut.
    static let maxIncoming = 4096

    /// A helper that does not say it (or says null, or only blanks) gives nil.
    static func optional(_ object: StrictObject, _ key: String) throws -> String? {
        guard let raw = try object.optionalString(key, maxLength: maxIncoming) else { return nil }
        return clean(raw)
    }

    public static func clean(_ raw: String) -> String? {
        let printable = String(String.UnicodeScalarView(raw.unicodeScalars.map(spaceForBlank).filter(isPrintable)))
        let words = printable.split(separator: " ", omittingEmptySubsequences: true)
        let text = String(words.joined(separator: " ").prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// Tabs and line breaks are blanks, not letters to drop.
    private static func spaceForBlank(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        CharacterSet.whitespacesAndNewlines.contains(scalar) ? " " : scalar
    }

    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        let category = scalar.properties.generalCategory
        return category != .control && category != .format && category != .surrogate && category != .privateUse && category != .unassigned
    }
}
