import Foundation
import MSCore

/// How the Apple `container` tool is called. Every call is a fixed program plus an argument list, so nothing a user typed
/// can become a flag: names and ids are checked against the id pattern first, and the image against the image pattern.
public enum AppleContainer {
    public static let namePrefix = "ms-"
    public static let defaultImage = "docker.io/library/ubuntu:24.04"
    public static let stopSignal = "SIGRTMIN+3"
    public static let stopSeconds = 30

    /// Where the start scripts tell the helper how the VM came up. The helper reads it back with `cat`, and only the two words in `InitMode` count.
    public static let initModeFile = "/metaservice-init-mode"

    /// The two extra rights the first try gets. systemd as the first process must mount /run and the other system folders (SYS_ADMIN) and set up the network (NET_ADMIN);
    /// without them the VM's first process quits at once. Each VM is its own small virtual machine, so the rights stay inside that VM; they are not rights on the Mac.
    /// The MAAS panel starts its VMs with the same two, written the same way, and that is verified on the Mac Studio.
    public static let systemdCapabilities = ["NET_ADMIN", "SYS_ADMIN"]

    /// How long the helper waits for a new VM to come up, and how long it then watches that it stays up. Whole seconds.
    public static let readySeconds = 60
    public static let settleSeconds = 3

    /// First try: install systemd if the image lacks it, give the machine an id, then hand over to systemd as the first process.
    /// If systemd cannot be installed the VM stays up as a plain VM instead of quitting. Fixed text; nothing is interpolated into it.
    public static let systemdScript = """
    # MetaService first start, with systemd. Fixed text: nothing from a request is ever put in here.

    # Called when systemd cannot be set up. The VM then stays up as a plain VM, so a terminal still opens and the person can see what went wrong.
    # The reason goes to the VM's own log (what "container logs" shows), and the word "plain" goes into the file the helper reads.
    stay_plain() {
      echo "metaservice: $1; this VM runs without systemd" >&2
      echo plain > \(initModeFile)
      exec sleep infinity
    }

    # Installs systemd the way Ubuntu and Debian images need it.
    install_systemd() {
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq && apt-get install -y -qq --no-install-recommends systemd systemd-sysv dbus libpam-systemd >/dev/null
    }

    # Three tries, three seconds apart, because the network inside a new VM can take a moment to work.
    install_systemd_with_retries() {
      tries=1
      until install_systemd; do
        [ "$tries" -lt 3 ] || return 1
        tries=$((tries + 1))
        sleep 3
      done
    }

    [ -x /sbin/init ] || install_systemd_with_retries || stay_plain "systemd could not be installed"
    [ -x /sbin/init ] || stay_plain "this image has no /sbin/init"
    [ -s /etc/machine-id ] || tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id
    echo systemd > \(initModeFile)
    exec /sbin/init
    """

    /// Second try, when systemd could not run: a first process that only keeps the VM alive. A terminal works; services such as systemd do not. Fixed text.
    public static let plainScript = """
    # MetaService first start, without systemd. Fixed text: nothing from a request is ever put in here.
    # "sleep infinity" waits forever, so the VM stays up and the terminal can open. The file tells the helper which way the VM came up.
    echo plain > \(initModeFile)
    exec sleep infinity
    """

    public static func name(for id: String) -> String { namePrefix + id }

    public static func id(fromName name: String) -> String? {
        name.hasPrefix(namePrefix) ? String(name.dropFirst(namePrefix.count)) : nil
    }

    /// The `run` arguments for one try. Names and sizes are separate arguments; the script is one of the two fixed texts above.
    public static func run(id: String, request: CreateWorkloadRequest, image: String, mode: InitMode = .systemd) -> [String] {
        ["run", "--detach", "--name", name(for: id), "--cpus", String(request.cpu), "--memory", "\(request.ramMb)M"]
            + (mode == .systemd ? systemdCapabilities.flatMap { ["--cap-add", $0] } : [])
            + ["--label", "metaservice.id=\(id)", image, "sh", "-c", mode == .systemd ? systemdScript : plainScript]
    }

    /// Fixed argument lists for reading what a VM printed: its own output, and the boot log of the small VM it runs in.
    public static func logs(_ id: String) -> [String] { ["logs", name(for: id)] }
    public static func bootLogs(_ id: String) -> [String] { ["logs", "--boot", name(for: id)] }

    /// Reads the file the start scripts wrote, to learn that the first-start script finished and how the VM came up.
    public static func initModeProbe(_ id: String) -> [String] { exec(id, arguments: ["cat", initModeFile], environment: [:]) }

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

    /// The arguments (after the tool's own path) for an interactive shell: `container exec -it <name> /bin/sh -l`. With an address that is a
    /// plain IPv4 address, the shell instead shows a root prompt that names it, like a normal VPS. A bad id is refused, not quoted; a bad
    /// address falls back to the login shell.
    public static func attach(_ id: String, address: String? = nil) throws -> [String] {
        guard Ids.isValid(id) else { throw EngineError.notFound }
        let interactive = ["exec", "-it"]
        guard let checked = checkedAddress(address) else { return interactive + [name(for: id), shellPath, loginShellArgument] }
        return interactive + ["-e", "\(promptVariable)=root@\(checked)\(promptEnd)"] + [name(for: id)] + promptShellArguments
    }

    public static let shellPath = "/bin/sh"

    /// A login shell: it reads /etc/profile, which is what a console without an address has always done.
    private static let loginShellArgument = "-l"
    /// The shell that shows the prompt, started through `sh -c` because a Linux guest's /bin/sh is dash: a bash that reads no profile or rc
    /// files, so nothing there can reset PS1. An image without bash keeps an interactive sh. The check for bash goes to /dev/null, never the
    /// shell itself: bash draws its prompt on standard error, so hiding that would hide the prompt.
    private static let promptShellScript = "command -v bash >/dev/null 2>&1 && exec bash --noprofile --norc -i; exec sh -i"
    private static let promptShellArguments = [shellPath, "-c", promptShellScript]
    /// The variable bash reads its prompt from; it goes in as `-e PS1=value`, never as part of the program text.
    private static let promptVariable = "PS1"
    /// The end of the root prompt: the working directory, then the usual root `# `.
    private static let promptEnd = ":\\w# "

    /// The address as canonical dotted text when it is a plain IPv4 address, else nil. Anything else (a shell word, a flag, an address with a
    /// prefix or a leading zero) is refused here, so no other text can reach the prompt.
    public static func checkedAddress(_ address: String?) -> String? {
        guard let address else { return nil }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [String] = []
        for part in parts {
            guard let value = Int(part), value >= 0, value <= 255, String(value) == part else { return nil }
            octets.append(String(value))
        }
        return octets.joined(separator: ".")
    }

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
    /// How the VM's first process ended, when the tool says so. The tool's JSON is not documented, so this is read where it is likely to be and is nil otherwise.
    public let exitCode: Int?

    public init(name: String, state: String, ipv4: String?, exitCode: Int? = nil) {
        self.name = name
        self.state = state
        self.ipv4 = ipv4
        self.exitCode = exitCode
    }
}

/// Reads the JSON `container list --format json` and `container inspect` print. Both give an object, or a list of them.
public enum ContainerJson {
    private static let maxItems = 5000

    /// The address of one workload in a listing, or nil when it is not listed or has none yet.
    public static func address(of id: String, in containers: [ContainerInfo]) -> String? {
        containers.first { $0.name == AppleContainer.name(for: id) }?.ipv4
    }

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
        let exitCode = (status?["exitCode"] as? Int) ?? (item["exitCode"] as? Int)
        return ContainerInfo(name: name, state: state, ipv4: address, exitCode: exitCode)
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
    /// True after the helper was asked to stop the VM, false after it was asked to start it (or made it). Nil in records written before this note existed.
    public var stopRequested: Bool?
    /// "systemd" or "plain": how the VM came up. Nil when unknown.
    public var initMode: String?

    public init(name: String, kind: String, cpu: Int, ramMb: Int, diskGb: Int, gpuMode: String, image: String, bundleVersion: String? = nil, stopRequested: Bool? = nil, initMode: String? = nil) {
        self.stopRequested = stopRequested
        self.initMode = initMode
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
