import Foundation
import MSCore

/// How the Apple `container` tool is called. Every call is a fixed program plus an argument list, so nothing a user typed
/// can become a flag: names and ids are checked against the id pattern first, and the image against the image pattern.
public enum AppleContainer {
    public static let namePrefix = "ms-"
    public static let defaultImage = "docker.io/library/ubuntu:24.04"
    public static let stopSignal = "SIGRTMIN+3"
    public static let stopSeconds = 30

    /// First boot installs systemd if the image lacks it, gives the machine an id, then hands over to systemd as PID 1.
    /// Same recipe the MAAS operator VMs use. It is fixed text; nothing is interpolated into it.
    public static let initScript = "[ -x /sbin/init ] || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq --no-install-recommends systemd systemd-sysv dbus libpam-systemd >/dev/null; }; [ -s /etc/machine-id ] || tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id; exec /sbin/init"

    public static func name(for id: String) -> String { namePrefix + id }

    public static func id(fromName name: String) -> String? {
        name.hasPrefix(namePrefix) ? String(name.dropFirst(namePrefix.count)) : nil
    }

    public static func run(id: String, request: CreateWorkloadRequest, image: String) -> [String] {
        ["run", "--detach", "--name", name(for: id), "--cpus", String(request.cpu), "--memory", "\(request.ramMb)M",
         "--label", "metaservice.id=\(id)", image, "sh", "-c", initScript]
    }

    public static func start(_ id: String) -> [String] { ["start", name(for: id)] }
    public static func stop(_ id: String) -> [String] { ["stop", "--signal", stopSignal, "--time", String(stopSeconds), name(for: id)] }
    public static func delete(_ id: String) -> [String] { ["delete", "--force", name(for: id)] }
    public static func inspect(_ id: String) -> [String] { ["inspect", name(for: id)] }
    public static func export(_ id: String, to path: String) -> [String] { ["export", "--output", path, name(for: id)] }
    public static func copyIn(_ id: String, from hostPath: String, to containerPath: String) -> [String] { ["cp", hostPath, "\(name(for: id)):\(containerPath)"] }

    /// Environment values go in as separate `-e NAME=value` pairs; they are never part of the program text.
    public static func exec(_ id: String, arguments: [String], environment: [String: String]) -> [String] {
        ["exec"] + environment.sorted { $0.key < $1.key }.flatMap { ["-e", "\($0.key)=\($0.value)"] } + [name(for: id)] + arguments
    }

    /// The arguments (after the tool's own path) for an interactive login shell: `container exec -it <name> /bin/sh -l`. A bad id is refused, not quoted.
    public static func attach(_ id: String) throws -> [String] {
        guard Ids.isValid(id) else { throw EngineError.notFound }
        return ["exec", "-it", name(for: id), shellPath, "-l"]
    }

    public static let shellPath = "/bin/sh"

    /// Installs the chat bundle inside a workload: python3 if missing, a locked-down user, the files, a systemd service, and a health check.
    /// Fixed text. The version and port arrive as MS_VERSION and MS_PORT; the archive and key were copied in beforehand.
    public static let bundleInstallScript = """
    set -e
    command -v python3 >/dev/null || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq --no-install-recommends python3 >/dev/null; }
    id -u metachat >/dev/null 2>&1 || useradd --system --home-dir /opt/metaservice --shell /usr/sbin/nologin metachat
    dir="/opt/metaservice/chat/$MS_VERSION"
    rm -rf "$dir"; mkdir -p "$dir"
    tar -xzf /tmp/metaservice-chat.tar.gz -C "$dir" --no-same-owner
    chown -R root:root /opt/metaservice/chat
    install -o metachat -g metachat -m 600 /tmp/metaservice-chat.key /opt/metaservice/chat.key
    install -d -o metachat -g metachat -m 700 /opt/metaservice/chat-data
    rm -f /tmp/metaservice-chat.tar.gz /tmp/metaservice-chat.key
    ln -sfn "$dir" /opt/metaservice/chat/current
    brain=""; if [ -n "$MS_BRAIN_URL" ]; then brain="--brain-url $MS_BRAIN_URL"; fi
    cat > /etc/systemd/system/metaservice-chat.service <<UNIT
    [Unit]
    Description=MetaService chat
    After=network.target
    [Service]
    User=metachat
    ReadWritePaths=/opt/metaservice/chat-data
    ExecStart=/usr/bin/python3 /opt/metaservice/chat/current/service/chat.py --port $MS_PORT --key-file /opt/metaservice/chat.key $brain
    Restart=always
    NoNewPrivileges=true
    ProtectSystem=strict
    ProtectHome=true
    PrivateTmp=true
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable metaservice-chat >/dev/null 2>&1
    systemctl restart metaservice-chat
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      python3 -c "import json,sys,urllib.request; sys.exit(0 if json.load(urllib.request.urlopen('http://127.0.0.1:$MS_PORT/health', timeout=2))['version'] == '$MS_VERSION' else 1)" 2>/dev/null && exit 0
      sleep 1
    done
    exit 1
    """

    /// Turns the chat off inside a workload: the service stops and is not started again, but /opt/metaservice/chat-data (the conversations) and the key stay.
    /// Fixed text; nothing is interpolated into it.
    public static let bundleUninstallScript = """
    systemctl disable --now metaservice-chat >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/metaservice-chat.service
    systemctl daemon-reload
    """

    public static let version = ["--version"]
    private static let versionPattern = #/\b(\d{1,4}\.\d{1,4}\.\d{1,4})\b/#

    /// The version in what `container --version` prints (for example "container CLI version 0.5.1 (build: release)"), or nil when there is none.
    public static func parseVersion(_ output: String) -> String? {
        output.firstMatch(of: versionPattern).map { String($0.output.1) }
    }

    public static let listAll = ["list", "--all", "--format", "json"]
    public static let systemStatus = ["system", "status"]
    public static let systemStart = ["system", "start"]
    public static func imageInspect(_ image: String) -> [String] { ["image", "inspect", image] }
    public static func imagePull(_ image: String) -> [String] { ["image", "pull", image] }
}

public struct ContainerInfo: Equatable {
    public let name: String
    public let state: String
    public let ipv4: String?

    public init(name: String, state: String, ipv4: String?) {
        self.name = name
        self.state = state
        self.ipv4 = ipv4
    }
}

/// Reads the JSON `container list --format json` and `container inspect` print. Both give an object, or a list of them.
public enum ContainerJson {
    private static let maxItems = 5000

    public static func parse(_ data: Data) -> [ContainerInfo] {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let items = (parsed as? [[String: Any]]) ?? (parsed as? [String: Any]).map { [$0] } ?? []
        return items.prefix(maxItems).compactMap(info)
    }

    private static func info(_ item: [String: Any]) -> ContainerInfo? {
        let configuration = item["configuration"] as? [String: Any]
        guard let name = item["id"] as? String ?? configuration?["id"] as? String, !name.isEmpty else { return nil }
        // Older tools nest the state and the networks under "status"; newer ones print the state as a plain word with "networks" beside it.
        let status = item["status"] as? [String: Any]
        let state = (status?["state"] as? String) ?? (item["status"] as? String) ?? "unknown"
        let networks = (status?["networks"] as? [[String: Any]]) ?? (item["networks"] as? [[String: Any]])
        let address = (networks?.first?["ipv4Address"] as? String)?.split(separator: "/").first.map(String.init)
        return ContainerInfo(name: name, state: state, ipv4: address)
    }
}

/// What the Agent remembers about each workload it made. The container tool has no disk-size setting and keeps no
/// MetaService numbers, so the Agent keeps them here and checks them against what is really running.
public struct WorkloadRecord: Codable, Equatable {
    public var name: String
    public var kind: String
    public var cpu: Int
    public var ramMb: Int
    public var diskGb: Int
    public var gpuMode: String
    public var image: String
    public var bundleVersion: String?

    public init(name: String, kind: String, cpu: Int, ramMb: Int, diskGb: Int, gpuMode: String, image: String, bundleVersion: String? = nil) {
        self.name = name
        self.kind = kind
        self.cpu = cpu
        self.ramMb = ramMb
        self.diskGb = diskGb
        self.gpuMode = gpuMode
        self.image = image
        self.bundleVersion = bundleVersion
    }
}

/// Turns the tool's state word into a workload state.
public enum ContainerStates {
    private static let mapped: Set<String> = ["running", "stopped", "exited", "created", "stopping", "removing", "starting"]

    /// The state words in a listing that `workloadState` does not know, each once and in order, so a new word of the tool is noticed.
    public static func unmappedWords(_ containers: [ContainerInfo]) -> [String] {
        Array(Set(containers.map(\.state).filter { !mapped.contains($0) })).sorted()
    }

    /// One line for the helper log. It holds only the tool's state word, never anything the person typed.
    public static func unmappedWarning(_ word: String) -> String {
        "container state word \"\(word)\" is not one the helper knows, so the VM is reported as failed"
    }

    public static func workloadState(_ raw: String?) -> WorkloadState {
        switch raw {
        case "running": return .running
        case "stopped", "exited", "created": return .stopped
        case "stopping", "removing": return .deleting
        case "starting": return .provisioning
        default: return .failed
        }
    }
}
