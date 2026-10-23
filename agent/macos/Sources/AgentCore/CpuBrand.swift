import Foundation

/// The name of this Mac's CPU (for example `Apple M4`), from `sysctl -n machdep.cpu.brand_string`.
/// The command is run by a function the caller gives, so a test can answer without a real Mac. A Mac that does not say gives nil and the fact is left out.
public enum CpuBrand {
    public static let sysctlPath = "/usr/sbin/sysctl"
    public static let sysctlArguments = ["-n", "machdep.cpu.brand_string"]
    public static let maxLength = 120

    public typealias Run = (_ executable: String, _ arguments: [String]) async throws -> Data

    public static func read(run: Run) async -> String? {
        guard let output = try? await run(sysctlPath, sysctlArguments) else { return nil }
        return clean(String(decoding: output, as: UTF8.self))
    }

    /// No control characters, single spaces, at most 120 characters; nil when nothing is left.
    public static func clean(_ raw: String) -> String? {
        let blanked = raw.unicodeScalars.map { CharacterSet.whitespacesAndNewlines.contains($0) ? " " : $0 }
        let printable = blanked.filter { $0.properties.generalCategory != .control }
        let words = String(String.UnicodeScalarView(printable)).split(separator: " ")
        let text = String(words.joined(separator: " ").prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
