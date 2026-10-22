import Foundation

/// Whether a login server is in the VM. The helper only reports it; installing or starting sshd is a question of the VM's image.
public enum SshdState: String, Codable, Equatable, Sendable {
    case running, installed, missing
}

public struct SshKeysResult: Encodable, Equatable {
    public let applied: Int
    public let sshd: SshdState

    public init(applied: Int, sshd: SshdState) {
        self.applied = applied
        self.sshd = sshd
    }
}

/// Writes the keys into root's `authorized_keys` of one VM and reports sshd, in ONE `container exec -i`. The keys travel on standard input only.
/// Where it lives: macOS helper, `Sources/AgentCore/SshKeys/`. The Linux helper runs the same script text through `incus exec`.
public enum SshKeysScript {
    public static let sshDirectory = "/root/.ssh"
    public static let keysFile = "/root/.ssh/authorized_keys"
    /// What the report line starts with; the state word follows it.
    public static let reportPrefix = "sshd="

    /// Fixed text: nothing from a request is ever put in here, and the keys are read from standard input by `cat`.
    /// The new content is written next to the real file and moved over it, so a login never sees a half-written list.
    /// sshd is "running" when a process is called sshd, "installed" when the program exists, "missing" otherwise.
    public static let text = """
    set -e
    umask 077
    mkdir -p \(sshDirectory)
    chmod 700 \(sshDirectory)
    cat > \(keysFile).new
    chmod 600 \(keysFile).new
    mv -f \(keysFile).new \(keysFile)
    if cat /proc/[0-9]*/comm 2>/dev/null | grep -qx sshd; then
      echo \(reportPrefix)running
    elif command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ]; then
      echo \(reportPrefix)installed
    else
      echo \(reportPrefix)missing
    fi
    """

    /// The `container exec` arguments (after the tool's own path). No key is in them; `-i` keeps standard input open for the keys.
    public static func arguments(id: String) -> [String] {
        ["exec", "-i", AppleContainer.name(for: id), AppleContainer.shellPath, "-c", text]
    }

    /// The state the script printed, or nil when the output has no report line (the script did not finish).
    public static func parseState(_ output: String) -> SshdState? {
        let reports = output.split(separator: "\n").filter { $0.hasPrefix(reportPrefix) }
        return reports.last.flatMap { SshdState(rawValue: String($0.dropFirst(reportPrefix.count))) }
    }

    /// Runs the script through `run` (program arguments and standard input) and reads its report. A missing report is a failure, not a guess.
    public static func apply(id: String, keys: [String], run: (_ arguments: [String], _ input: Data) async throws -> String) async throws -> SshKeysResult {
        let output = try await run(arguments(id: id), SshKeyLines.fileContent(keys))
        guard let state = parseState(output) else { throw EngineError.failed("the VM did not report whether sshd is there") }
        return SshKeysResult(applied: keys.count, sshd: state)
    }
}
