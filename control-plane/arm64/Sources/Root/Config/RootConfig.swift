import Foundation
import RootCore

struct ConfigError: Error, CustomStringConvertible {
    let description: String
}

/// Settings come from a protected env file on the Root machine (never from the panel) plus a few command-line options.
struct RootConfig {
    /// The operator listener (panel and /api). It has no sign-in, so it only ever binds to this machine.
    var port = 9100
    var bind = "127.0.0.1"
    /// The listener Agents and chats reach (enroll, heartbeat, bundle download, AI proxy). Every route on it needs its own token.
    /// It stays on this machine until the operator gives it a LAN address.
    var agentListenPort = 9102
    var agentListenBind = "127.0.0.1"
    var publicBaseURL = "http://localhost:9100"
    var databasePath: String
    var uiDirectory = "../../frontend/dist"
    var bundleDirectory: String?
    var scanSubnet: Subnet?
    var nmapPath: String?
    var arpPath = "/usr/sbin/arp"
    var agentPort = 9101
    var routerURL: String?
    var routerUser: String?
    var routerPassword: String?
    var routerCertSha256: String?
    var setupToken: String?
    /// The computer the control plane runs on is listed as the first machine. Tests turn this off.
    var localMachine = true
    var envFile = RootConfig.defaultEnvFile
    var aiBaseURL: String?
    var aiApiKey: String?
    var aiModel: String?
    var aiMaxTokens = BrainRules.defaultMaxTokens
    var capabilitySeconds = BrainRules.defaultCapabilitySeconds

    var cookiesAreSecure: Bool { publicBaseURL.hasPrefix("https://") }
    var sessionCookieName: String { cookiesAreSecure ? "__Host-ms_session" : "ms_session" }
    var aiConfigured: Bool { [aiBaseURL, aiApiKey, aiModel].allSatisfy { $0?.isEmpty == false } }

    /// As in the MAAS panel: the env file and the data sit with the control plane, in the folder it is started from (control-plane/arm64).
    static let defaultEnvFile = ".env"
    static let defaultDatabase = "state/root.sqlite3"
}

enum ConfigLoader {
    static func load(arguments: [String]) throws -> RootConfig {
        let options = try parseOptions(arguments)
        var config = RootConfig(databasePath: options["--db"] ?? RootConfig.defaultDatabase)
        let envPath = options["--env-file"] ?? RootConfig.defaultEnvFile
        config.envFile = envPath
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
            if name == "--no-local-machine" {
                result[name] = "1"
                index += 1
                continue
            }
            guard ["--env-file", "--db", "--port", "--bind", "--agent-port", "--agent-bind", "--public-url", "--ui-dir", "--bundle-dir"].contains(name), index + 1 < arguments.count else {
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
        if let text = options["--agent-port"] {
            guard let port = Int(text), (1...65535).contains(port) else { throw ConfigError(description: "bad agent port") }
            config.agentListenPort = port
        }
        config.localMachine = options["--no-local-machine"] == nil
        config.bind = options["--bind"] ?? config.bind
        config.agentListenBind = options["--agent-bind"] ?? config.agentListenBind
        guard OperatorGate.isLoopback(config.bind) else {
            throw ConfigError(description: "the operator listener has no sign-in, so it must bind to this machine (127.0.0.1); put a proxy with its own access control in front for remote use")
        }
        config.publicBaseURL = options["--public-url"] ?? config.publicBaseURL
        config.uiDirectory = options["--ui-dir"] ?? config.uiDirectory
        config.bundleDirectory = options["--bundle-dir"] ?? config.bundleDirectory
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
            let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !unquoted.isEmpty { values[key] = unquoted } // a blank value means "not set", so the example file can be copied as it is
        }
        return values
    }

    static func apply(_ env: [String: String], to config: inout RootConfig) throws {
        config.publicBaseURL = env["PUBLIC_BASE_URL"] ?? config.publicBaseURL
        config.bind = env["ROOT_BIND"] ?? config.bind
        config.agentListenBind = env["ROOT_AGENT_BIND"] ?? config.agentListenBind
        if let text = env["ROOT_AGENT_PORT"] {
            guard let port = Int(text), (1...65535).contains(port) else { throw ConfigError(description: "bad ROOT_AGENT_PORT") }
            config.agentListenPort = port
        }
        if let text = env["ROOT_PORT"] {
            guard let port = Int(text), (1...65535).contains(port) else { throw ConfigError(description: "bad ROOT_PORT") }
            config.port = port
        }
        try applyScan(env, to: &config)
        try applyBrain(env, to: &config)
        if let token = env["ROOT_SETUP_TOKEN"] {
            guard token.count >= SetupGate.minLength else { throw ConfigError(description: "ROOT_SETUP_TOKEN must be at least \(SetupGate.minLength) characters") }
            config.setupToken = token
        }
    }

    /// The AI provider. The key lives only in this file; a half-filled set of settings is refused so a typo is not mistaken for "not configured".
    static func applyBrain(_ env: [String: String], to config: inout RootConfig) throws {
        config.aiBaseURL = env["AI_BASE_URL"].flatMap { $0.isEmpty ? nil : $0 }
        config.aiApiKey = env["AI_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        config.aiModel = env["AI_DEFAULT_MODEL"].flatMap { $0.isEmpty ? nil : $0 }
        config.aiMaxTokens = try number(env["AI_MAX_TOKENS"], named: "AI_MAX_TOKENS", in: BrainRules.maxTokensRange, default: config.aiMaxTokens)
        config.capabilitySeconds = try number(env["AI_CAPABILITY_SECONDS"], named: "AI_CAPABILITY_SECONDS", in: BrainRules.capabilitySecondsRange, default: config.capabilitySeconds)
        let given = [config.aiBaseURL, config.aiApiKey, config.aiModel].compactMap { $0 }
        guard !given.isEmpty else { return }
        guard given.count == 3 else { throw ConfigError(description: "AI_BASE_URL, AI_API_KEY and AI_DEFAULT_MODEL must all be set, or none of them") }
        guard BrainRules.isAcceptableBaseURL(config.aiBaseURL!) else { throw ConfigError(description: "AI_BASE_URL must be https (or http to a private address) with no credentials in it") }
    }

    private static func number(_ text: String?, named name: String, in range: ClosedRange<Int>, default fallback: Int) throws -> Int {
        guard let text else { return fallback }
        guard let value = Int(text), range.contains(value) else { throw ConfigError(description: "\(name) must be a whole number from \(range.lowerBound) to \(range.upperBound)") }
        return value
    }

    /// Scan settings. The subnet and the router must be private addresses; an operator can never type a target.
    static func applyScan(_ env: [String: String], to config: inout RootConfig) throws {
        if let text = env["SCAN_SUBNET"] {
            guard let subnet = Subnet(cidr: text), subnet.isPrivate else { throw ConfigError(description: "SCAN_SUBNET must be a private network no wider than /22") }
            config.scanSubnet = subnet
        }
        config.nmapPath = env["NMAP_PATH"]
        config.arpPath = env["ARP_PATH"] ?? config.arpPath
        if let text = env["AGENT_PORT"] {
            guard let port = Int(text), (1...65535).contains(port) else { throw ConfigError(description: "bad AGENT_PORT") }
            config.agentPort = port
        }
        config.routerUser = env["ROUTER_USER"]
        config.routerPassword = env["ROUTER_PASSWORD"]
        config.routerCertSha256 = env["ROUTER_CERT_SHA256"]?.lowercased()
        config.routerURL = try env["ROUTER_URL"].map(routerHost)
    }

    /// The router must be a plain IPv4 address (http or https for RouterOS 7, api or api-ssl for the binary API). Whether it sits inside the scan subnet is checked when a scan starts.
    static func routerHost(_ text: String) throws -> String {
        guard let url = URL(string: text), ["http", "https", "api", "api-ssl"].contains(url.scheme), let host = url.host, IPv4.isValid(host), url.user == nil else {
            throw ConfigError(description: "ROUTER_URL must be http, https, api or api-ssl with an IPv4 address and no credentials in it")
        }
        return text
    }
}
