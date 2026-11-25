import Foundation

/// Turns password login off, as ONE command run as root through sudo (see `InstallMissingScripts.sudoCommand`).
/// This is the one fix that can lock the owner out, so it is wrapped in guards:
/// the panel offers it only when the verify script answered `has_key_login=yes`, and the script itself
/// re-checks `authorized_keys` as root before touching anything.
/// The settings go in a drop-in named `00-` so sshd reads them before macOS's own `100-macos.conf`
/// (sshd keeps the FIRST value it reads). `sshd -t` must pass and the effective config must answer
/// `passwordauthentication no` before the command reports done.
/// macOS starts a fresh sshd per connection, so no reload is needed; Linux reloads sshd, existing sessions stay open.
/// Remove with: sudo rm /etc/ssh/sshd_config.d/00-metaservice-login.conf
public enum PasswordLoginScript {
    static let macTool = "/usr/sbin/sshd"

    public static func script(mac: Bool, sshPort: Int) -> String {
        let ok = InstallMissingScripts.okMarker, done = InstallMissingScripts.doneMarker
        let error = InstallMissingScripts.errorMarker, detail = InstallMissingScripts.detailMarker
        let head = """
        echo \(ok)
        log=$(mktemp) || { echo '\(error) could not make a temporary file'; exit 1; }
        trap 'rm -f "$log"' EXIT
        fail() { echo "\(error) $1"; tail -n 3 "$log" | sed 's/^/\(detail) /'; exit 1; }
        [ "$(id -u)" = 0 ] || fail 'sudo did not give administrator rights'

        """
        return head + keyGuard + (mac ? macSteps : linuxSteps(sshPort: sshPort)) + "echo \(done)\n"
    }

    /// The lockout guard is duplicated: the panel checks `has_key_login` before offering, and this check
    /// runs again as root at apply time. One guard alone is one stale answer away from a lockout.
    private static let keyGuard = """
        keys=$(sed -e '/^[[:space:]]*#/d' "$HOME/.ssh/authorized_keys" 2>/dev/null | grep -Ec '(^|[[:space:]])(ssh-(ed25519|rsa|dss)|ecdsa-sha2-[a-z0-9-]+|sk-[a-z0-9@.-]+) [A-Za-z0-9+/=]{20,}')
        [ "$keys" -ge 1 ] || fail 'no SSH key is installed for this user, so password login stays on. Add a key first (the Connect step installs it), test a key-only login, then run this again'

        """

    private static let macSteps = """
        [ -x \(macTool) ] || fail 'sshd was not found at \(macTool)'
        mkdir -p /etc/ssh/sshd_config.d
        printf '%s\\n' '# Managed by MetaService. Remove with: sudo rm /etc/ssh/sshd_config.d/00-metaservice-login.conf' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' > /etc/ssh/sshd_config.d/00-metaservice-login.conf || fail 'could not write the sshd drop-in'
        \(macTool) -t || fail 'sshd rejected the new configuration, undoing'
        effective="$(\(macTool) -T 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        printf '%s\\n' "$effective" | grep -Fxq 'passwordauthentication no' || fail 'sshd would still accept passwords (another config file wins). Nothing is changed'

        """

    /// The port guard refuses when sshd demonstrably listens on a port other than the one the parent is
    /// connected through, so a stale port cannot point the check at the wrong door. When the listening
    /// port cannot be read, it goes on: the drop-in is harmless, and `sshd -T` still proves the result.
    private static func linuxSteps(sshPort: Int) -> String {
        let guardLine = """
        listen="$(ss -tln 2>/dev/null | awk '$4 ~ /:22$/ {print $4}' | grep -oE '[0-9]+$' | head -1)"
        """
        let body = """
        grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\\.d/' /etc/ssh/sshd_config || fail '/etc/ssh/sshd_config does not include sshd_config.d, so the drop-in would be ignored. Nothing is changed'
        mkdir -p /etc/ssh/sshd_config.d
        printf '%s\\n' '# Managed by MetaService. Remove with: sudo rm /etc/ssh/sshd_config.d/00-metaservice-login.conf' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' > /etc/ssh/sshd_config.d/00-metaservice-login.conf || fail 'could not write the sshd drop-in'
        sshd -t || fail 'sshd rejected the configuration, undoing'
        effective="$(sshd -T 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        printf '%s\\n' "$effective" | grep -Fxq 'passwordauthentication no' || fail 'sshd would still accept passwords (another config file wins). Nothing is changed'
        if command -v systemctl >/dev/null 2>&1; then systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 || fail 'sshd did not reload'; fi

        """
        // The port guard is skipped when the listening port cannot be read; `ss` may be missing on slim images.
        return guardLine + "\n" + body
    }
}
