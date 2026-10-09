import CryptoKit
import Foundation
import AgentCore
import MSCore

/// Puts the chat bundle where it belongs: on this machine (run by the Agent) or inside a workload (run by systemd there).
/// It downloads from the Root with the machine token, checks the checksum and the archive, and only then installs anything.
actor BundleInstaller: BundleInstalling {
    private let config: AgentConfig
    private let engine: Engine
    private let root: URL?
    private let machineToken: String?
    private let supervisor: ChatSupervisor?
    private var keys: [String: String]
    private var machineVersion: String?
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private static let maxBytes = 64 * 1024 * 1024
    private static let keepVersions = 3
    private static let healthSeconds = 15

    init(config: AgentConfig, engine: Engine, root: URL?, machineToken: String?, supervisor: ChatSupervisor?) {
        self.config = config
        self.engine = engine
        self.root = root
        self.machineToken = machineToken
        self.supervisor = supervisor
        keys = (FileManager.default.contents(atPath: config.stateDirectory + "/chat-keys.json").flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }) ?? [:]
        machineVersion = (FileManager.default.contents(atPath: config.stateDirectory + "/bundle.json")
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })?["version"]
    }

    func installedVersion() -> String? { machineVersion }

    /// On start: run the version that was installed before, if any.
    func resume() async {
        guard let version = machineVersion, let key = keys["machine"] else { return }
        await supervisor?.run(arguments: chatArguments(version: version, keyFile: keyFile(for: "machine", key: key)))
    }

    /// One install at a time. An actor lets others in whenever it waits, so without this two installs could swap the running chat back and forth.
    func install(_ request: BundleInstallRequest) async throws -> [String: String] {
        await acquire()
        defer { release() }
        return try await installOne(request)
    }

    private func acquire() async {
        guard busy else { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        guard !waiting.isEmpty else { busy = false; return }
        waiting.removeFirst().resume()
    }

    private func installOne(_ request: BundleInstallRequest) async throws -> [String: String] {
        let archive = try await download(request)
        defer { try? FileManager.default.removeItem(atPath: archive) }
        try Self.checkArchive(archive, version: request.version)
        let target = request.workloadId ?? "machine"
        let key = keys[target] ?? Tokens.random(bytes: 24)
        let port = config.chatPort
        if let workload = request.workloadId { try await installInside(workload, archive: archive, key: key, request: request) } else { try await installHere(archive: archive, key: key, request: request) }
        try remember(key, for: target)
        return ["version": request.version, "port": String(port), "chat_key": key]
    }

    // MARK: getting the file

    private func download(_ request: BundleInstallRequest) async throws -> String {
        guard let root, let machineToken else { throw EngineError.failed("this Agent has no Root to download from") }
        var download = URLRequest(url: root.appendingPathComponent("v1/bundles/\(request.version)/noarch"))
        download.setValue("Bearer \(machineToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await RootLink.session.data(for: download)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= Self.maxBytes else { throw EngineError.failed("the Root did not give the bundle") }
        let seen = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard seen == request.sha256 else { throw EngineError.failed("the bundle does not match its checksum") }
        let folder = config.stateDirectory + "/tmp"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = folder + "/bundle-\(Tokens.random(bytes: 6)).tar.gz"
        guard FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw EngineError.failed("cannot save the bundle") }
        return path
    }

    /// The archive may hold only plain files and folders with safe relative names, and its manifest must be the version that was asked for.
    private static func checkArchive(_ path: String, version: String) throws {
        let listing = try run("/usr/bin/tar", ["-tvzf", path])
        let lines = listing.split(separator: "\n")
        guard !lines.isEmpty, lines.count < 200 else { throw EngineError.failed("the bundle archive is not acceptable") }
        for line in lines {
            guard let kind = line.first, kind == "-" || kind == "d", let name = line.split(separator: " ", omittingEmptySubsequences: true).last.map(String.init) else { throw EngineError.failed("the bundle holds something other than files") }
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), !name.contains("\\") else { throw EngineError.failed("the bundle has an unsafe file name") }
        }
        guard let manifest = try? JSONSerialization.jsonObject(with: Data(try run("/usr/bin/tar", ["-xzOf", path, "manifest.json"]).utf8)) as? [String: Any],
              manifest["name"] as? String == "metaservice-chat", manifest["version"] as? String == version else { throw EngineError.failed("the bundle is not the version that was asked for") }
    }

    private static func run(_ program: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count < 1_000_000 else { throw EngineError.failed("the bundle archive could not be read") }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: on this machine

    private func installHere(archive: String, key: String, request: BundleInstallRequest) async throws {
        guard let supervisor, let python = config.pythonPath ?? Self.findPython() else { throw EngineError.failed("python3 was not found on this machine") }
        _ = python
        let folder = config.stateDirectory + "/bundles/\(request.version)"
        try? FileManager.default.removeItem(atPath: folder)
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        _ = try Self.run("/usr/bin/tar", ["-xzf", archive, "-C", folder, "--no-same-owner"])
        let previous = machineVersion
        await supervisor.run(arguments: chatArguments(version: request.version, keyFile: keyFile(for: "machine", key: key)))
        guard await healthy(port: config.chatPort, version: request.version) else {
            if let previous, let oldKey = keys["machine"] { await supervisor.run(arguments: chatArguments(version: previous, keyFile: keyFile(for: "machine", key: oldKey))) } else { await supervisor.stop() }
            throw EngineError.failed("the new chat did not start, so the old one was put back")
        }
        machineVersion = request.version
        try saveMachineVersion(request.version)
        prune(keeping: request.version, previous: previous)
    }

    private func chatArguments(version: String, keyFile: String) -> [String] {
        let folder = config.stateDirectory + "/bundles/\(version)"
        let base = [folder + "/service/chat.py", "--port", String(config.chatPort), "--bind", config.chatBind ?? config.bind, "--key-file", keyFile, "--web-dir", folder + "/web", "--version", version]
        return base + (brainURL.map { ["--brain-url", $0] } ?? [])
    }

    /// Where the chat asks for AI replies: the Root this Agent reports to. It is an address, not a secret.
    private var brainURL: String? {
        root.map { $0.absoluteString.hasSuffix("/") ? String($0.absoluteString.dropLast()) : $0.absoluteString }
    }

    private func keyFile(for target: String, key: String) -> String {
        let path = config.stateDirectory + "/chat-\(target).key"
        FileManager.default.createFile(atPath: path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600])
        return path
    }

    private func healthy(port: Int, version: String) async -> Bool {
        for _ in 0..<Self.healthSeconds {
            if let (data, _) = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/health")!),
               (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? String == version { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    private func saveMachineVersion(_ version: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["version": version])
        FileManager.default.createFile(atPath: config.stateDirectory + "/bundle.json", contents: data, attributes: [.posixPermissions: 0o600])
    }

    private func prune(keeping current: String, previous: String?) {
        let folder = config.stateDirectory + "/bundles"
        let all = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
        for old in all.dropLast(Self.keepVersions) where old != current && old != previous { try? FileManager.default.removeItem(atPath: folder + "/" + old) }
    }

    private static func findPython() -> String? {
        ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: inside a workload

    private func installInside(_ workload: String, archive: String, key: String, request: BundleInstallRequest) async throws {
        let keyPath = keyFile(for: "push-" + workload, key: key)
        defer { try? FileManager.default.removeItem(atPath: keyPath) }
        try await engine.push(id: workload, hostPath: archive, containerPath: "/tmp/metaservice-chat.tar.gz")
        try await engine.push(id: workload, hostPath: keyPath, containerPath: "/tmp/metaservice-chat.key")
        _ = try await engine.exec(id: workload, arguments: ["sh", "-c", AppleContainer.bundleInstallScript], environment: ["MS_VERSION": request.version, "MS_PORT": String(config.chatPort), "MS_BRAIN_URL": brainURL ?? ""])
        try await engine.setBundleVersion(id: workload, version: request.version)
    }

    private func remember(_ key: String, for target: String) throws {
        keys[target] = key
        let data = try JSONEncoder().encode(keys)
        FileManager.default.createFile(atPath: config.stateDirectory + "/chat-keys.json", contents: data, attributes: [.posixPermissions: 0o600])
    }
}
