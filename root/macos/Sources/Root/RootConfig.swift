import Foundation

struct ConfigError: Error, CustomStringConvertible {
    let description: String
}

/// Settings come from a protected env file on the Root machine (never from the panel) plus a few command-line options.
struct RootConfig {
    var port = 9100
    var bind = "127.0.0.1"
    var publicBaseURL = "http://localhost:9100"
    var databasePath: String
    var uiDirectory = "ui/dist"
    var googleClientId: String?
    var googleClientSecret: String?
    var allowedEmails: Set<String> = []

    var cookiesAreSecure: Bool { publicBaseURL.hasPrefix("https://") }
    var sessionCookieName: String { cookiesAreSecure ? "__Host-ms_session" : "ms_session" }
    var oauthCookieName: String { cookiesAreSecure ? "__Host-ms_oauth" : "ms_oauth" }
    var googleConfigured: Bool { googleClientId?.isEmpty == false && googleClientSecret?.isEmpty == false }
    var callbackURL: String { publicBaseURL + "/auth/callback" }

    static let defaultDirectory = ("~/.metaservice" as NSString).expandingTildeInPath
    static let defaultEnvFile = defaultDirectory + "/root.env"
    static let defaultDatabase = defaultDirectory + "/root.sqlite3"
}

enum ConfigLoader {
    static func load(arguments: [String]) throws -> RootConfig {
        let options = try parseOptions(arguments)
        var config = RootConfig(databasePath: options["--db"] ?? RootConfig.defaultDatabase)
        let envPath = options["--env-file"] ?? RootConfig.defaultEnvFile
        if FileManager.default.fileExists(atPath: envPath) {
            try requireProtected(envPath)
            try apply(try parseEnv(String(contentsOfFile: envPath, encoding: .utf8)), to: &config)
        }
        try applyOptions(options, to: &config)
        return config
    }

    static func parseOptions(_ arguments: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let name = arguments[index]
            guard ["--env-file", "--db", "--port", "--bind", "--public-url", "--ui-dir"].contains(name), index + 1 < arguments.count else {
                throw ConfigError(description: "unknown or incomplete option \(name)")
            }
            result[name] = arguments[index + 1]
            index += 2
        }
        return result
    }

    static func applyOptions(_ options: [String: String], to config: inout RootConfig) throws {
        if let text = options["--port"] {
            guard let port = Int(text), (1...65535).contains(port) else { throw ConfigError(description: "bad port") }
            config.port = port
        }
        config.bind = options["--bind"] ?? config.bind
        config.publicBaseURL = options["--public-url"] ?? config.publicBaseURL
        config.uiDirectory = options["--ui-dir"] ?? config.uiDirectory
    }

    /// A file holding secrets must not be readable by anyone but its owner.
    static func requireProtected(_ path: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard mode & 0o077 == 0 else { throw ConfigError(description: "\(path) must be mode 600 (owner only)") }
    }

    static func parseEnv(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            values[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return values
    }

    static func apply(_ env: [String: String], to config: inout RootConfig) throws {
        config.googleClientId = env["GOOGLE_CLIENT_ID"]
        config.googleClientSecret = env["GOOGLE_CLIENT_SECRET"]
        config.allowedEmails = Set((env["ALLOWED_EMAILS"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
        config.publicBaseURL = env["PUBLIC_BASE_URL"] ?? config.publicBaseURL
        config.bind = env["ROOT_BIND"] ?? config.bind
        if let text = env["ROOT_PORT"] {
            guard let port = Int(text), (1...65535).contains(port) else { throw ConfigError(description: "bad ROOT_PORT") }
            config.port = port
        }
    }
}
