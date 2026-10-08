import Foundation

public enum MacAddress {
    /// "a:1B:2c:3:4:5f" and "A1-B2-..." both become "0A:1B:2C:03:04:5F". Anything else is nil.
    public static func normalize(_ text: String) -> String? {
        let parts = text.uppercased().split(whereSeparator: { $0 == ":" || $0 == "-" }).map(String.init)
        guard parts.count == 6, parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        let padded = parts.map { $0.count == 1 ? "0" + $0 : $0 }
        guard padded.joined() != "000000000000", padded.joined() != "FFFFFFFFFFFF" else { return nil }
        return padded.joined(separator: ":")
    }
}
