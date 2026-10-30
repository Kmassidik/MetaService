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
    var routePath = "/sbin/route"
    var digPath = "/usr/bin/dig"
    var agentPort = 9101
    var routerURL: String?
    var routerUser: String?
    var routerPassword: String?
    var routerCertSha256: String?
    var setupToken: String?
    /// The MetaService program that is copied to other computers.
    var agentBinary = "../../agent/macos/.build/debug/metaservice-agent"
    /// Connecting to other computers: loopback is a legal target only when this is on (tests and demos), and the Agent builds for other systems may sit in one folder.
    var remoteAllowLoopback = false
    /// Where the programs for other systems are looked for (metaservice-agent-linux-x86_64 and so on). Without a setting it is state/agent-builds, so a build only needs to be put there.
    var agentBuildsDirectory: String? = "state/agent-builds"
    /// Which engine an Agent installed on another computer is started with. Empty means the right one for its system (apple on a Mac, incus on Linux); tests and demos use "simulated".
    var remoteEngine: String?
    /// Logins the parent allows itself on one other computer in a minute. A flood of logins looks like an attack to the network, so the default is small.
    var remoteTriesPerMinute = 4
    /// Seconds between the history readings of a machine. Ten in real use; a test shortens it.
    var historyIntervalSeconds = StatsHistory.intervalSeconds
    var envFile = RootConfig.defaultEnvFile
    var aiBaseURL: String?
    var aiApiKey: String?
    var aiModel: String?
    var aiMaxTokens = BrainRules.defaultMaxTokens
    var capabilitySeconds = BrainRules.defaultCapabilitySeconds
    /// The sandbox domain: the API is `api.<domain>` and everything inside a sandbox is `<port>-<id>.<domain>` (see
    /// sandbox/README.md). Set once per deployment, because E2B's SDKs build every address from it; never in a route.
    var sandboxDomain = RootConfig.defaultSandboxDomain
    /// The join-share hub's admin listener and the file holding its key (Share a PC page). Without the address the feature is off.
    var joinShareAdminURL: String?
    var joinShareAdminKeyFile: String?

    var cookiesAreSecure: Bool { publicBaseURL.hasPrefix("https://") }
    var sessionCookieName: String { cookiesAreSecure ? "__Host-ms_session" : "ms_session" }
    var aiConfigured: Bool { [aiBaseURL, aiApiKey, aiModel].allSatisfy { $0?.isEmpty == false } }

    /// As in the MAAS panel: the env file and the data sit with the control plane, in the folder it is started from (control-plane/arm64).
    static let defaultEnvFile = ".env"
    static let defaultDatabase = "state/root.sqlite3"
    /// Chosen for this deployment until the sandbox domain is final (sandbox/README.md, "Addresses").
    /// Deliberately `ruvio.site`, not `sandbox.ruvio.site`: E2B's SDK builds `{port}-{id}.{domain}` and `api.{domain}`, and a
    /// second level (`x.sandbox.ruvio.site`) is not covered by Cloudflare's free Universal SSL, which only covers one wildcard
    /// level. With this value every address is `*.ruvio.site` and the free certificate covers it.
    static let defaultSandboxDomain = "ruvio.site"
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
        config.agentBinary = absolutePath(config.agentBinary)
        config.agentBuildsDirectory = config.agentBuildsDirectory.map(absolutePath)
        return config
    }

    /// A path from wherever the Root was started, written out in full: the Agent is started later by other code, and macOS cannot find it through a path like "../../agent/...".
    static func absolutePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func parseOptions(_ arguments: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let name = arguments[index]
            guard ["--env-file", "--db", "--port", "--bind", "--agent-port", "--agent-bind", "--agent-binary", "--public-url", "--ui-dir", "--bundle-dir", "--remote-allow-loopback", "--agent-builds-dir", "--remote-engine", "--remote-tries", "--history-interval"].contains(name), index + 1 < arguments.count else {
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
        config.agentBinary = options["--agent-binary"] ?? config.agentBinary
        config.bind = options["--bind"] ?? config.bind
        config.agentListenBind = options["--agent-bind"] ?? config.agentListenBind
        guard OperatorGate.isLoopback(config.bind) else {
            throw ConfigError(description: "the operator listener has no sign-in, so it must bind to this machine (127.0.0.1); put a proxy with its own access control in front for remote use")
        }
        config.publicBaseURL = options["--public-url"] ?? config.publicBaseURL
        config.uiDirectory = options["--ui-dir"] ?? config.uiDirectory
        config.bundleDirectory = options["--bundle-dir"] ?? config.bundleDirectory
        config.remoteAllowLoopback = options["--remote-allow-loopback"].map { ["yes", "true", "1"].contains($0.lowercased()) } ?? config.remoteAllowLoopback
        config.agentBuildsDirectory = options["--agent-builds-dir"] ?? config.agentBuildsDirectory
        config.remoteEngine = options["--remote-engine"] ?? config.remoteEngine
        config.remoteTriesPerMinute = try number(options["--remote-tries"], named: "--remote-tries", in: 1...60, default: config.remoteTriesPerMinute)
        config.historyIntervalSeconds = try number(options["--history-interval"], named: "--history-interval", in: historyIntervalRange, default: config.historyIntervalSeconds)
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
        config.agentBinary = env["AGENT_BINARY"] ?? config.agentBinary
        config.agentBuildsDirectory = env["AGENT_BUILDS_DIR"] ?? config.agentBuildsDirectory
        config.remoteAllowLoopback = env["ROOT_REMOTE_ALLOW_LOOPBACK"].map { ["yes", "true", "1"].contains($0.lowercased()) } ?? config.remoteAllowLoopback
        if let text = env["ROOT_AGENT_PORT"] {
            guard let port = Int(text), (1...65535).contains(port) else { throw ConfigError(description: "bad ROOT_AGENT_PORT") }
            config.agentListenPort = port
        }
        if let text = env["ROOT_PORT"] {
            guard let port = Int(text), (1...65535).contains(port) else { throw ConfigError(description: "bad ROOT_PORT") }
            config.port = port
        }
        config.historyIntervalSeconds = try number(env["HISTORY_INTERVAL_SECONDS"], named: "HISTORY_INTERVAL_SECONDS", in: historyIntervalRange, default: config.historyIntervalSeconds)
        try applyScan(env, to: &config)
        try applyBrain(env, to: &config)
        try applySandboxes(env, to: &config)
        try applyJoinShare(env, to: &config)
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

    /// The join-share hub. Off when the address is not set; set, it needs the key file too (a half-filled pair is refused so a typo is not mistaken for "off").
    /// The key itself stays in its file, which is read at every call.
    static func applyJoinShare(_ env: [String: String], to config: inout RootConfig) throws {
        guard let url = env["JOIN_SHARE_ADMIN_URL"] else { return }
        guard JoinShareRules.isAcceptableAdminURL(url) else {
            throw ConfigError(description: "JOIN_SHARE_ADMIN_URL must be an https address (http only for 127.0.0.1 or localhost) with no login, path or query in it")
        }
        guard let keyFile = env["JOIN_SHARE_ADMIN_KEY_FILE"] else { throw ConfigError(description: "JOIN_SHARE_ADMIN_URL needs JOIN_SHARE_ADMIN_KEY_FILE as well") }
        config.joinShareAdminURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        config.joinShareAdminKeyFile = absolutePath((keyFile as NSString).expandingTildeInPath)
    }

    /// The sandbox domain, as a host name: lowercase letters, digits, dots and dashes. It is never a URL (the SDK adds
    /// `api.` and `<port>-<id>.` itself), so anything with a scheme or a slash is refused at start.
    static func applySandboxes(_ env: [String: String], to config: inout RootConfig) throws {
        guard let text = env["SANDBOX_DOMAIN"] else { return }
        config.sandboxDomain = try hostName(text, named: "SANDBOX_DOMAIN")
    }

    static func hostName(_ text: String, named name: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard !text.isEmpty, text.count <= 253, text.unicodeScalars.allSatisfy(allowed.contains),
              !text.hasPrefix("."), !text.hasSuffix("."), text.contains(".") else {
            throw ConfigError(description: "\(name) must be a lowercase host name such as sandbox.example.com")
        }
        return text
    }

    /// One second at the shortest (for tests), one minute at the longest.
    static let historyIntervalRange = 1...60

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
        config.routePath = env["ROUTE_PATH"] ?? config.routePath
        config.digPath = env["DIG_PATH"] ?? config.digPath
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
