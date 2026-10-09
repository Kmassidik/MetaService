import Foundation

/// The name this computer gets in the panel: its host name, made safe for the machine name rules (lowercase letters, digits and dashes).
public enum LocalMachineName {
    public static let fallback = "this-machine"
    private static let maxLength = 63

    public static func make(from hostName: String) -> String {
        let firstLabel = hostName.split(separator: ".").first.map(String.init) ?? ""
        let cleaned = firstLabel.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? String($0) : "-" }.joined()
        let trimmed = String(cleaned.drop(while: { $0 == "-" }).prefix(maxLength))
        let name = String(trimmed.reversed().drop(while: { $0 == "-" }).reversed())
        return Ids.isValid(name) ? name : fallback
    }
}
