import CryptoKit
import Foundation

/// Which build of this program runs: the lowercase hex SHA-256 of the program's own file. The version text stays the same from one build to the next, so this is what lets the parent
/// tell an old helper from a new one.
public enum AgentBuild {
    private static let pieceBytes = 1 << 20

    /// The build of the program that is running now. Worked out once, then kept; nil when the file cannot be read.
    public static func ofRunningProgram() -> String? { running }

    private static let running: String? = Bundle.main.executablePath.flatMap(sha256(ofFileAt:))

    public static func sha256(ofFileAt path: String) -> String? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), !isFolder.boolValue, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while let piece = try? handle.read(upToCount: pieceBytes), !piece.isEmpty { hash.update(data: piece) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
