import Foundation

public enum SudoAccess: String, Equatable, Sendable {
    case none, password, passwordless
}

/// What a computer says about itself when asked over SSH. All of it is untrusted text from another computer: it is cut to a short
/// printable line, and anything unknown is ignored.
public struct RemoteFacts: Equatable, Sendable {
    public var os = ""
    public var arch = ""
    public var user = ""
    public var home = ""
    /// The name the computer calls itself (`hostname -s`), the readable default for the machine's name.
    public var hostname = ""
    public var version = ""
    public var chip = ""
    public var cpuCores: Int?
    public var ramMb: Int?
    public var diskFreeGb: Int?
    public var kvm: Bool?
    /// True when the CPU itself says it can virtualise (`svm` on AMD, `vmx` on Intel). nil when that computer did not say, which is not the same as "no".
    public var virt: Bool?
    /// True when a qemu program for this chip is on the PATH (`qemu-system-x86_64` or `qemu-system-aarch64`). nil when it was not asked (macOS).
    public var qemu: Bool?
    public var tools: Set<String> = []
    /// The name of the first NVIDIA card `nvidia-smi -L` lists, or nil when there is no such card (or no such program).
    public var nvidiaGpu: String?
    public var sudo: SudoAccess = .none
    /// The package manager of a Linux computer, when it is one MetaService knows.
    public var packageManager: PackageManager?
    public var port9101Free: Bool?
    /// True when what listens on the port is MetaService's own program from an earlier install, which an install can replace.
    public var port9101Ours = false
    /// True when this computer's helper is registered with the system's boot service (a LaunchDaemon on a Mac, a systemd unit on Linux), so it comes back by
    /// itself after a restart. Only asked about a computer that already has a box of ours: a computer without one has nothing to register, so this stays nil.
    public var autostart: Bool?

    public init() {}

    /// True when the NVIDIA container toolkit is there (either of its programs).
    public var hasGpuToolkit: Bool { tools.contains("nvidia-ctk") || tools.contains("nvidia-container-cli") }

    /// Where MetaService's folder is on that computer: the folder the install makes, next to the home folder. Empty when it did not say where its home is.
    public var box: String { home.isEmpty ? "" : home + "/" + RemoteInstallOptions.boxFolderName }

    public var isMac: Bool { os == "Darwin" }
    public var isLinux: Bool { os == "Linux" }
    public var isWindows: Bool { os == Self.windows }
    public static let windows = "Windows"

    /// The name the parent's Agent builds go by: "darwin-arm64", "linux-x86_64", "linux-arm64".
    public var agentBuild: String {
        let family = os.lowercased()
        let chip = ["arm64", "aarch64"].contains(arch) ? "arm64" : arch
        return "\(family)-\(chip)"
    }
}

public enum RemoteProbe {
    /// One shell script, sent to `sh -s` on the other computer: it only reads. One login gives every fact.
    public static let script = """
    PATH="$PATH:/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/snap/bin:/usr/sbin:/sbin"
    os=$(uname -s)
    echo "os=$os"
    echo "arch=$(uname -m)"
    echo "user=$(id -un)"
    echo "host=$(hostname -s 2>/dev/null)"
    echo "home=$HOME"
    if [ "$os" = Darwin ]; then
      echo "version=macOS $(sw_vers -productVersion 2>/dev/null)"
      echo "chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
      echo "cpu=$(sysctl -n hw.ncpu 2>/dev/null)"
      echo "ram_mb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576 ))"
    else
      echo "version=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
      echo "chip=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//')"
      echo "cpu=$(nproc 2>/dev/null)"
      echo "ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)"
      if [ -e /dev/kvm ]; then echo "kvm=yes"; else echo "kvm=no"; fi
      case "$(uname -m)" in
        x86_64|amd64)
          if grep -qwE 'svm|vmx' /proc/cpuinfo 2>/dev/null; then echo "virt=yes"
          elif [ -r /proc/cpuinfo ]; then echo "virt=no"
          else echo "virt=unknown"; fi ;;
        *) echo "virt=unknown" ;;
      esac
      # A full VM needs three things, and Ubuntu 24.04 splits the last two off: what runs it (qemu-system-*), what reads its image
      # (qemu-img, in qemu-utils), and the SPICE display module (qemu-system-modules-spice). Incus uses all three, so any one
      # missing must make this "no" — otherwise the panel offers nothing and the first create fails.
      # `-spice help` exits 1 even when the module is there, so the answer is read from its output, never from its status.
      qemu=$(command -v qemu-system-x86_64 2>/dev/null || command -v qemu-system-aarch64 2>/dev/null)
      spice=no
      if [ -n "$qemu" ] && "$qemu" -spice help 2>&1 | grep -q 'spice options'; then spice=yes; fi
      if [ -n "$qemu" ] && command -v qemu-img >/dev/null 2>&1 && [ "$spice" = yes ]; then echo "qemu=yes"; else echo "qemu=no"; fi
    fi
    echo "disk_free_gb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')"
    # Whether the helper of this computer starts again at boot. Only asked when a box of ours is there: another computer's folder is never looked at.
    if [ -d "$HOME/\(RemoteInstallOptions.boxFolderName)" ]; then
      if [ "$os" = Darwin ]; then boot_unit=\(AutostartScript.macPath)
      else boot_unit=\(AutostartScript.linuxPath); fi
      if [ -f "$boot_unit" ]; then echo "autostart=yes"; else echo "autostart=no"; fi
    fi
    if [ "$os" = Linux ] && command -v nvidia-smi >/dev/null 2>&1; then
      card=$(nvidia-smi -L 2>/dev/null | sed -n 's/^GPU 0: //p' | sed 's/ (UUID.*//' | head -1)
      [ -n "$card" ] && echo "nvidia_gpu=$card"
    fi
    for tool in container incus python3 curl tar nvidia-ctk nvidia-container-cli; do command -v "$tool" >/dev/null 2>&1 && echo "tool=$tool"; done
    for manager in apt-get:apt dnf:dnf pacman:pacman zypper:zypper apk:apk; do
      if command -v "${manager%%:*}" >/dev/null 2>&1; then echo "pkg=${manager##*:}"; break; fi
    done
    if sudo -n true >/dev/null 2>&1; then echo "sudo=passwordless"
    elif command -v sudo >/dev/null 2>&1; then echo "sudo=password"
    else echo "sudo=none"; fi
    if command -v lsof >/dev/null 2>&1; then
      holder=$(lsof -t -nP -iTCP:9101 -sTCP:LISTEN 2>/dev/null | head -1)
      if [ -z "$holder" ]; then echo "port_9101=free"
      elif ps -p "$holder" -o command= 2>/dev/null | grep -q metaservice-agent; then echo "port_9101=ours"
      else echo "port_9101=busy"; fi
    elif command -v ss >/dev/null 2>&1; then
      if ! ss -ltn 2>/dev/null | grep -q ':9101 '; then echo "port_9101=free"
      elif ss -ltnp 2>/dev/null | grep ':9101 ' | grep -q metaservice-agent; then echo "port_9101=ours"
      else echo "port_9101=busy"; fi
    fi
    """

    /// A Windows computer answers the check with its own error, not with facts: all that is known about it is who logged in.
    public static func windows(user: String) -> RemoteFacts {
        var facts = RemoteFacts()
        facts.os = RemoteFacts.windows
        facts.user = user
        return facts
    }

    private static let knownTools: Set<String> = ["container", "incus", "python3", "curl", "tar", "nvidia-ctk", "nvidia-container-cli"]
    private static let longestValue = 120

    /// Reads the script's answer. Nothing without an OS and a chip type is useful, so that is nil.
    public static func parse(_ text: String) -> RemoteFacts? {
        var facts = RemoteFacts()
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            apply(key: key, value: clean(String(line[line.index(after: equals)...])), to: &facts)
        }
        return facts.os.isEmpty || facts.arch.isEmpty ? nil : facts
    }

    private static func clean(_ value: String) -> String {
        let printable = value.unicodeScalars.filter { $0.value >= 32 && $0.value < 127 }
        return String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces).prefix(longestValue).description
    }

    private static func apply(key: String, value: String, to facts: inout RemoteFacts) {
        switch key {
        case "os": facts.os = value
        case "arch": facts.arch = value
        case "user": facts.user = value
        case "home": facts.home = value
        case "host": facts.hostname = value
        case "version": facts.version = value
        case "chip": facts.chip = value
        case "cpu": facts.cpuCores = Int(value)
        case "ram_mb": facts.ramMb = Int(value)
        case "disk_free_gb": facts.diskFreeGb = Int(value)
        case "nvidia_gpu": facts.nvidiaGpu = value.isEmpty ? nil : value
        case "kvm": facts.kvm = flag(value)
        case "virt": facts.virt = flag(value)
        case "qemu": facts.qemu = flag(value)
        case "autostart": facts.autostart = flag(value)
        case "tool": if knownTools.contains(value) { facts.tools.insert(value) }
        case "pkg": facts.packageManager = PackageManager(rawValue: value)
        case "sudo": facts.sudo = SudoAccess(rawValue: value) ?? .none
        case "port_9101": facts.port9101Free = value == "free" || value == "ours"; facts.port9101Ours = value == "ours"
        default: break
        }
    }

    /// A yes or no answer. Anything else (an `unknown` line, or a word this parser does not know) is "did not find out", never a made-up no.
    private static func flag(_ value: String) -> Bool? {
        switch value {
        case "yes": return true
        case "no": return false
        default: return nil
        }
    }
}
