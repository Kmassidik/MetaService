import Foundation

/// Why the SSH server could not be made to listen in a VM. The raw value is what the script prints; `message` is what the person reads.
public enum SshdFailure: String, Error, Equatable, Sendable {
    case noPackageManager = "no_package_manager"
    case installFailed = "install_failed"
    case configInvalid = "config_invalid"
    case notListening = "not_listening"

    /// The error code of the 502 answer.
    public static let errorCode = "sshd_install_failed"

    public var message: String {
        switch self {
        case .noPackageManager: "The VM has no package manager the helper knows (apt, apk, dnf, yum), so it cannot install the SSH server."
        case .installFailed: "The VM could not download the SSH server. Check that the VM has internet access."
        case .configInvalid: "The SSH server did not accept its settings, so nothing was changed."
        case .notListening: "The SSH server was installed but is not listening on port 22."
        }
    }
}

/// What the install script printed.
public struct SshdInstallReport: Equatable, Sendable {
    public let sshd: SshdState
    public let installed: Bool
    public let failure: SshdFailure?

    public init(sshd: SshdState, installed: Bool, failure: SshdFailure?) {
        self.sshd = sshd
        self.installed = installed
        self.failure = failure
    }
}

/// Installs, locks to keys only, and starts the SSH server inside one VM, in ONE `container exec` of fixed text (request flag `install_sshd`).
/// Where it lives: macOS helper, `Sources/AgentCore/SshKeys/`. The Linux helper has the same script text in `agent/linux/src/ssh_install.rs`.
/// It runs AFTER the keys are written (see `SshKeysScript`), so a stuck or failed install never loses keys. No standard input, no request data.
public enum SshdInstallScript {
    private static let installedPrefix = "installed="
    private static let failurePrefix = "failure="

    /// Fixed text: it installs the server when it is missing (apt-get, apk, dnf, yum in that order), makes it key-only, starts it, and prints
    /// `sshd=<state>`, `installed=true|false` and, when something went wrong, `failure=<code>`. Package manager noise is thrown away inside the VM.
    public static let text = """
    PATH="$PATH:/usr/sbin:/sbin:/usr/local/sbin"
    umask 022
    MAIN=/etc/ssh/sshd_config
    DROPIN_DIR=/etc/ssh/sshd_config.d
    DROPIN=/etc/ssh/sshd_config.d/10-metaservice.conf
    BEGIN_MARK='# BEGIN metaservice'
    END_MARK='# END metaservice'
    WORK=/tmp/metaservice-ssh.$$
    NO_MANAGER=2
    WAIT_TRIES=10
    installed=false
    changed=false
    mkdir -p "$WORK"

    settings() {
    cat <<'EOF'
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitRootLogin prohibit-password
    PubkeyAuthentication yes
    EOF
    }

    has_sshd() { command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ]; }
    is_running() { cat /proc/[0-9]*/comm 2>/dev/null | grep -qx sshd; }
    is_listening() { cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -Eq '^ *[0-9]+: [0-9A-Fa-f]+:0016 [0-9A-Fa-f]+:[0-9A-Fa-f]+ 0A '; }
    is_up() { is_running && is_listening; }

    report() {
      if is_up; then state=running
      elif has_sshd; then state=installed
      else state=missing
      fi
      rm -rf "$WORK"
      echo "sshd=$state"
      echo "installed=$installed"
      [ -z "$1" ] || echo "failure=$1"
      exit 0
    }

    install_package() {
      if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update </dev/null >/dev/null 2>&1 &&
          DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server </dev/null >/dev/null 2>&1
      elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache openssh </dev/null >/dev/null 2>&1
      elif command -v dnf >/dev/null 2>&1; then
        dnf -y install openssh-server </dev/null >/dev/null 2>&1
      elif command -v yum >/dev/null 2>&1; then
        yum -y install openssh-server </dev/null >/dev/null 2>&1
      else
        return "$NO_MANAGER"
      fi
    }

    ensure_package() {
      install_package
      status=$?
      [ "$status" -ne "$NO_MANAGER" ] || report no_package_manager
      [ "$status" -eq 0 ] || report install_failed
      installed=true
      has_sshd || report install_failed
    }

    same_file() { [ -f "$2" ] && [ "$(cat "$1")" = "$(cat "$2")" ]; }

    write_dropin() {
      mkdir -p "$DROPIN_DIR"
      settings > "$DROPIN.new"
      same_file "$DROPIN.new" "$DROPIN" && { rm -f "$DROPIN.new"; return 0; }
      if [ -f "$DROPIN" ]; then cp -p "$DROPIN" "$WORK/dropin.old"; else : > "$WORK/dropin.created"; fi
      mv -f "$DROPIN.new" "$DROPIN"
      changed=true
    }

    write_main_block() {
      { echo "$BEGIN_MARK"; settings; echo "$END_MARK"; sed "/$BEGIN_MARK/,/$END_MARK/d" "$MAIN"; } > "$MAIN.new"
      same_file "$MAIN.new" "$MAIN" && { rm -f "$MAIN.new"; return 0; }
      cp -p "$MAIN" "$WORK/main.old"
      mv -f "$MAIN.new" "$MAIN"
      changed=true
    }

    has_include() { grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config[.]d/[*][.]conf' "$MAIN" 2>/dev/null; }

    restore_config() {
      [ ! -f "$WORK/dropin.old" ] || cp -p "$WORK/dropin.old" "$DROPIN"
      [ ! -f "$WORK/dropin.created" ] || rm -f "$DROPIN"
      [ ! -f "$WORK/main.old" ] || cp -p "$WORK/main.old" "$MAIN"
    }

    apply_config() {
      write_dropin
      has_include || write_main_block
      sshd -t </dev/null >/dev/null 2>&1 && return 0
      restore_config
      report config_invalid
    }

    systemd_unit() {
      for candidate in ssh sshd; do
        systemctl cat "$candidate.service" </dev/null >/dev/null 2>&1 && { echo "$candidate"; return 0; }
      done
      return 1
    }

    reload_plain() {
      [ "$changed" = false ] && return 0
      [ -r /run/sshd.pid ] && kill -HUP "$(cat /run/sshd.pid)" 2>/dev/null
      return 0
    }

    start_plain() {
      is_running && { reload_plain; return 0; }
      mkdir -p /run/sshd
      sshd </dev/null >/dev/null 2>&1
    }

    start_systemd() {
      unit=$(systemd_unit) || return 1
      systemctl enable --now "$unit" </dev/null >/dev/null 2>&1 || return 1
      [ "$changed" = false ] && return 0
      systemctl reload "$unit" </dev/null >/dev/null 2>&1 || systemctl restart "$unit" </dev/null >/dev/null 2>&1
    }

    start_server() {
      [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && start_systemd && return 0
      start_plain
    }

    wait_until_up() {
      tries=0
      while [ "$tries" -lt "$WAIT_TRIES" ] && ! is_up; do
        sleep 1
        tries=$((tries + 1))
      done
    }

    has_sshd || ensure_package
    ssh-keygen -A </dev/null >/dev/null 2>&1
    mkdir -p /run/sshd
    apply_config
    start_server
    wait_until_up
    is_up || report not_listening
    report
    """

    /// The `container exec` arguments (after the tool's own path). Nothing from a request is in them.
    public static func arguments(id: String) -> [String] {
        ["exec", AppleContainer.name(for: id), AppleContainer.shellPath, "-c", text]
    }

    /// Reads the script's lines. Nil when there is no `sshd=` line (the script did not finish) or a failure code is not one we know.
    public static func parseReport(_ output: String) -> SshdInstallReport? {
        func value(_ prefix: String) -> String? {
            output.split(separator: "\n").last { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        guard let sshd = SshKeysScript.parseState(output) else { return nil }
        let code = value(failurePrefix)
        let failure = code.flatMap { SshdFailure(rawValue: $0) }
        guard code == nil || failure != nil else { return nil }
        return SshdInstallReport(sshd: sshd, installed: value(installedPrefix) == "true", failure: failure)
    }

    /// Runs the script through `run` (program arguments) and reads its report. A run that fails or takes too long, or prints no report, is `installFailed`; nothing is guessed.
    public static func install(id: String, run: (_ arguments: [String]) async throws -> String) async throws -> SshdInstallReport {
        let output: String
        do { output = try await run(arguments(id: id)) } catch EngineError.failed { throw SshdFailure.installFailed }
        guard let report = parseReport(output) else { throw SshdFailure.installFailed }
        return report
    }
}
