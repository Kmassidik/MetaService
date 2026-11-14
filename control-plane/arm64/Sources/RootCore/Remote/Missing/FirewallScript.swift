import Foundation

/// Turns the firewall on, as ONE command run as root through sudo (see `InstallMissingScripts.sudoCommand`).
/// A Mac uses Apple's own firewall tool; macOS keeps Remote Login (SSH) working. A Linux computer uses ufw, and the SSH port the parent is connected through is
/// allowed FIRST, so turning the firewall on cannot cut this connection or lock the owner out. With no ufw nothing is changed.
public enum FirewallScript {
    static let macTool = "/usr/libexec/ApplicationFirewall/socketfilterfw"

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
        return head + (mac ? macSteps : linuxSteps(sshPort: sshPort)) + "echo \(done)\n"
    }

    private static let macSteps = """
    [ -x \(macTool) ] || fail 'the Mac firewall tool was not found'
    \(macTool) --setglobalstate on >"$log" 2>&1 || fail 'turning the firewall on did not work'
    \(macTool) --getglobalstate 2>/dev/null | grep -q 'State = [12]' || fail 'the firewall is still off after turning it on'

    """

    /// The port is a number checked by the caller; it is written as a number, never as text from the other computer.
    private static func linuxSteps(sshPort: Int) -> String {
        let port = max(1, min(sshPort, 65_535))
        return """
        command -v ufw >/dev/null 2>&1 || fail 'this computer has no ufw firewall, so nothing was changed. Install ufw, or use the firewall your system already has'
        ufw allow \(port)/tcp >"$log" 2>&1 || fail 'could not allow the SSH port first, so the firewall was not turned on'
        ufw --force enable >"$log" 2>&1 || fail 'turning the firewall on did not work'
        ufw status 2>/dev/null | grep -qi 'Status: active' || fail 'the firewall is still off after turning it on'

        """
    }
}
