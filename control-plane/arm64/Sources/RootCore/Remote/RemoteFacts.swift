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
    public var version = ""
    public var chip = ""
    public var cpuCores: Int?
    public var ramMb: Int?
    public var diskFreeGb: Int?
    public var kvm: Bool?
    public var tools: Set<String> = []
    public var sudo: SudoAccess = .none
    public var port9101Free: Bool?

    public init() {}

    public var isMac: Bool { os == "Darwin" }
    public var isLinux: Bool { os == "Linux" }

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
    fi
    echo "disk_free_gb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')"
    for tool in container incus python3 curl tar; do command -v "$tool" >/dev/null 2>&1 && echo "tool=$tool"; done
    if sudo -n true >/dev/null 2>&1; then echo "sudo=passwordless"
    elif command -v sudo >/dev/null 2>&1; then echo "sudo=password"
    else echo "sudo=none"; fi
    if command -v lsof >/dev/null 2>&1; then
      if lsof -nP -iTCP:9101 -sTCP:LISTEN >/dev/null 2>&1; then echo "port_9101=busy"; else echo "port_9101=free"; fi
    elif command -v ss >/dev/null 2>&1; then
      if ss -ltn 2>/dev/null | grep -q ':9101 '; then echo "port_9101=busy"; else echo "port_9101=free"; fi
    fi
    """

    private static let knownTools: Set<String> = ["container", "incus", "python3", "curl", "tar"]
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
        case "version": facts.version = value
        case "chip": facts.chip = value
        case "cpu": facts.cpuCores = Int(value)
        case "ram_mb": facts.ramMb = Int(value)
        case "disk_free_gb": facts.diskFreeGb = Int(value)
        case "kvm": facts.kvm = value == "yes"
        case "tool": if knownTools.contains(value) { facts.tools.insert(value) }
        case "sudo": facts.sudo = SudoAccess(rawValue: value) ?? .none
        case "port_9101": facts.port9101Free = value == "free"
        default: break
        }
    }
}
