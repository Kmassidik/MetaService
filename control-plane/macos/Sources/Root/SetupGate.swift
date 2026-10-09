import Foundation
import MSCore

/// The first-run lock, as in the MAAS panel: until the admin login exists, creating it needs the setup token.
/// The token comes from `ROOT_SETUP_TOKEN` in the protected env file, or the Root makes one and keeps it in a mode-600 file next to the database.
/// Once the admin exists the gate closes for good and the file is removed.
final class SetupGate: @unchecked Sendable {
    static let fileName = "setup.token"
    static let minLength = 16
    private let lock = NSLock()
    private var token: String?
    private let file: String

    init(token: String?, file: String) {
        self.token = token
        self.file = file
    }

    /// The gate for this start: closed if the admin exists, otherwise open with the configured token or a stored or new one.
    static func prepare(configured: String?, adminExists: Bool, directory: String) throws -> SetupGate {
        let file = directory + "/" + fileName
        guard !adminExists else {
            try? FileManager.default.removeItem(atPath: file)
            return SetupGate(token: nil, file: file)
        }
        if let configured { return SetupGate(token: configured, file: file) }
        if let stored = try? String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), stored.count >= minLength {
            return SetupGate(token: stored, file: file)
        }
        let made = Tokens.random()
        guard FileManager.default.createFile(atPath: file, contents: Data((made + "\n").utf8), attributes: [.posixPermissions: 0o600]) else {
            throw ConfigError(description: "cannot write the setup token file \(file)")
        }
        return SetupGate(token: made, file: file)
    }

    var isOpen: Bool { lock.withLock { token != nil } }

    func accepts(_ given: String) -> Bool {
        lock.withLock { token.map { Tokens.constantTimeEqual($0, given) } ?? false }
    }

    func close() {
        lock.withLock { token = nil }
        try? FileManager.default.removeItem(atPath: file)
    }

    var path: String { file }
}
