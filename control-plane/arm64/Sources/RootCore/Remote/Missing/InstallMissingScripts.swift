import Foundation

/// The commands that install a missing part on a Debian or Ubuntu computer. Written once here, run as root through sudo as ONE command (see `sudoCommand`): sudo keeps no
/// ticket between two logins that have no terminal, so a second command would ask for the password again.
public enum InstallMissingScripts {
    public static let okMarker = "ms-sudo-ok"
    public static let doneMarker = "ms-done"
    public static let errorMarker = "ms-error:"
    public static let detailMarker = "ms-detail:"
    public static let incusGroup = "incus-admin"

    /// The command line for ssh: sudo reads the password from standard input (`-S`, empty prompt), or never asks (`-n`) for a login that needs none. The script is an argument,
    /// so standard input is free for the password and nothing else. English messages (`LC_ALL=C`), so they can be told apart.
    public static func sudoCommand(script: String, withPassword: Bool) -> String {
        "LC_ALL=C LANGUAGE=C sudo \(withPassword ? "-S" : "-n") -p '' -- sh -c \(Shell.quote(script))"
    }

    public static func script(for part: MissingPart, user: String) -> String {
        prelude + body(for: part, user: user) + "echo \(doneMarker)\n"
    }

    private static func body(for part: MissingPart, user: String) -> String {
        switch part {
        case .vmTool: return incus(user: user)
        case .python: return python
        }
    }

    private static let prelude = """
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 APT_LISTCHANGES_FRONTEND=none
    echo \(okMarker)
    log=$(mktemp) || { echo '\(errorMarker) could not make a temporary file'; exit 1; }
    trap 'rm -f "$log"' EXIT
    explain() {
      if grep -qi 'could not get lock' "$log"; then echo 'another program is using the package manager (an update may be running): try again in a few minutes'
      elif grep -qi 'dpkg was interrupted' "$log"; then echo 'an earlier install was interrupted: run `sudo dpkg --configure -a` on that computer, then try again'
      elif grep -qiE 'could not resolve|temporary failure resolving|failed to fetch|unable to connect|connection (timed out|failed)' "$log"; then echo 'that computer could not reach the internet to download the package'
      else echo "$1"; fi
    }
    fail() { echo "\(errorMarker) $(explain "$1")"; tail -n 3 "$log" | sed 's/^/\(detailMarker) /'; exit 1; }
    [ "$(id -u)" = 0 ] || fail 'sudo did not give administrator rights'
    aptget() {
      tries=0
      while :; do
        apt-get -y -o Dpkg::Options::=--force-confold -o DPkg::Lock::Timeout=120 "$@" >"$log" 2>&1 && return 0
        grep -qi 'could not get lock' "$log" || return 1
        tries=$((tries + 1))
        [ "$tries" -lt 12 ] || return 1
        sleep 10
      done
    }
    aptget update || fail 'the package list could not be updated'

    """

    private static let python = """
    aptget install python3 || fail 'installing python3 did not work'
    command -v python3 >/dev/null 2>&1 || fail 'python3 is still missing after the install'

    """

    private static func incus(user: String) -> String {
        """
        candidate=$(apt-cache policy incus 2>/dev/null | awk '/Candidate:/ {print $2}')
        case "$candidate" in ''|'(none)') fail 'this version of the system has no Incus package (Debian 13 and Ubuntu 24.04 or newer have one). Nothing was installed' ;; esac
        aptget install incus || fail 'installing incus did not work'
        command -v incus >/dev/null 2>&1 || fail 'incus is still missing after the install'
        incus admin waitready --timeout 60 >"$log" 2>&1 || fail 'Incus was installed but did not start'
        if ! incus profile device list default 2>/dev/null | grep -qx root; then
          incus admin init --minimal >"$log" 2>&1 || fail 'Incus was installed but could not be set up'
        fi
        getent group \(incusGroup) >/dev/null 2>&1 || fail 'the \(incusGroup) group is missing after the install'
        usermod -a -G \(incusGroup) \(Shell.quote(user)) >"$log" 2>&1 || fail 'the user could not be added to the \(incusGroup) group'

        """
    }
}
