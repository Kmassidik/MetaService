import Foundation
import MSCore

/// The first-run lock, as in the MAAS panel (`PANEL_SETUP_TOKEN` in its protected .env): until the admin login exists, creating it needs the setup token.
/// The token lives in the Root's protected env file as `ROOT_SETUP_TOKEN`. If the file has none on a first run, the Root makes one and writes it into that file (mode 600),
/// so the operator reads it from there. Once the admin exists the gate is closed for good.
final class SetupGate: @unchecked Sendable {
    static let variable = "ROOT_SETUP_TOKEN"
    static let minLength = 16
    private let lock = NSLock()
    private var token: String?
    let envFile: String

    init(token: String?, envFile: String) {
        self.token = token
        self.envFile = envFile
    }

    /// The gate for this start: closed if the admin exists, open with the env file's token, or open with a new token that was just written to the env file.
    static func prepare(configured: String?, adminExists: Bool, envFile: String) throws -> SetupGate {
        guard !adminExists else { return SetupGate(token: nil, envFile: envFile) }
        if let configured { return SetupGate(token: configured, envFile: envFile) }
        let made = Tokens.random()
        let existing = (try? String(contentsOfFile: envFile, encoding: .utf8)) ?? ""
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let text = existing + separator + "# first-run setup token, made by the Root; creating the admin login needs it\n\(variable)=\(made)\n"
        let temporary = envFile + ".new"
        guard FileManager.default.createFile(atPath: temporary, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]),
              rename(temporary, envFile) == 0 else {
            try? FileManager.default.removeItem(atPath: temporary)
            throw ConfigError(description: "cannot write \(variable) into \(envFile)")
        }
        return SetupGate(token: made, envFile: envFile)
    }

    var isOpen: Bool { lock.withLock { token != nil } }

    func accepts(_ given: String) -> Bool {
        lock.withLock { token.map { Tokens.constantTimeEqual($0, given) } ?? false }
    }

    func close() {
        lock.withLock { token = nil }
    }
}
