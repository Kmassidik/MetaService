import Foundation

/// The read-only security look at a computer that has no MetaService helper yet: ONE shell script, sent to `sh -s` over a login like the first check's.
/// It prints strict `key=value` lines (read by `RemoteSecurityParse`) and changes nothing: it only reads files and asks `systemctl show`, `socketfilterfw`,
/// `defaults export`, `apt list` and `softwareupdate -l`. Each key means what the same key means in the helpers' own baseline
/// (agent/linux/src/security/baseline, agent/macos/.../BaselineChecks.swift); only the helper is not there yet, so the same rules are read by shell.
public enum SecurityVerifyScript {
    /// The first line of the script. A fake computer in the black-box checks tells this script from the first check by it.
    public static let marker = "# metaservice-security-baseline"
    public static let linuxPendingSeconds = 30
    public static let macPendingSeconds = 60
    /// The whole look may take this long: the one slow question plus the quick ones.
    public static let totalSeconds: TimeInterval = 100

    private static let firewallTool = Shell.quote("/usr/libexec/ApplicationFirewall/socketfilterfw")
    private static let softwareUpdateDomain = Shell.quote("/Library/Preferences/com.apple.SoftwareUpdate")
    private static let maxIncludeDepth = 8

    public static let script = make(root: "")

    /// `root` is put in front of the sshd files and exists for tests, which point the script at a folder of their own; on a real computer it is empty.
    public static func make(root: String) -> String {
        [marker, common, sshd(root: root), linux(root: root), mac, main].joined(separator: "\n")
    }

    private static let common = #"""
    PATH="$PATH:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin"
    set -f
    say() { printf '%s=%s\n' "$1" "$2"; }
    """#

    /// password_login: the first PasswordAuthentication sshd reads wins, `Include` is expanded where it stands, a `Match` line ends that file, nothing said means yes.
    private static func sshd(root: String) -> String {
        let rootPrefix = Shell.quote(root)
        let sshDirectory = Shell.quote(root + "/etc/ssh")
        let sshdConfig = Shell.quote(root + "/etc/ssh/sshd_config")
        return #"""
    PW=
    sshd_lines() {
      local file="$1" depth="$2" line key value pattern oldifs
      [ "$depth" -le \#(maxIncludeDepth) ] || return 1
      [ -r "$file" ] || return 1
      while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        oldifs="$IFS"; IFS="$(printf ' \t=')"; set -- $line; IFS="$oldifs"
        [ $# -gt 0 ] || continue
        key=$(printf '%s' "$1" | tr 'A-Z' 'a-z'); shift
        value=$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | tr -d '"')
        [ "$key" != match ] || return 0
        [ "$key" != passwordauthentication ] || [ -n "$PW" ] || PW="$value"
        [ -z "$PW" ] || return 0
        [ "$key" = include ] || continue
        for pattern in "$@"; do
          sshd_include "$pattern" "$depth" || return 1
        done
        [ -z "$PW" ] || return 0
      done < "$file"
    }
    sshd_include() {
      local pattern="$1" depth="$2" found
      case "$pattern" in /*) pattern=\#(rootPrefix)"$pattern" ;; *) pattern=\#(sshDirectory)/"$pattern" ;; esac
      set +f
      for found in $pattern; do
        set -f
        [ -e "$found" ] || continue
        [ -z "$PW" ] || break
        sshd_lines "$found" $((depth + 1)) || return 1
      done
      set -f
    }
    password_login() {
      sshd_lines \#(sshdConfig) 0 || { echo unknown; return; }
      [ "$PW" = no ] && { echo no; return; }
      echo yes
    }
    """#
    }

    private static func linux(root: String) -> String {
        let ufwConfig = Shell.quote(root + "/etc/ufw/ufw.conf")
        let autoUpgrades = Shell.quote(root + "/etc/apt/apt.conf.d/20auto-upgrades")
        return #"""
    unit_field() { systemctl show -p LoadState,ActiveState,UnitFileState "$1" 2>/dev/null | sed -n "s/^$2=//p" | head -1; }
    ban_unit() {
      [ -n "$(unit_field "$1" LoadState)" ] || return 0
      [ "$(unit_field "$1" ActiveState)" = active ] && { echo running; return; }
      echo not_running
    }
    ban_tool_linux() {
      command -v systemctl >/dev/null 2>&1 || { echo unknown; return; }
      answers=" $(ban_unit fail2ban.service) $(ban_unit sshguard.service) "
      case "$answers" in *" running "*) echo running; return ;; esac
      case "$answers" in *" not_running "*) echo not_running; return ;; esac
      echo unknown
    }
    ufw_state() {
      [ -r \#(ufwConfig) ] || { echo unknown; return; }
      value=$(sed -n 's/^[[:space:]]*ENABLED[[:space:]]*=[[:space:]]*"\{0,1\}\([A-Za-z]*\).*/\1/p' \#(ufwConfig) | head -1 | tr 'A-Z' 'a-z')
      [ "$value" = yes ] && { echo yes; return; }
      echo no
    }
    firewall_linux() {
      [ "$(ufw_state)" = yes ] && { echo yes; return; }
      [ "$(unit_field firewalld.service ActiveState)" = active ] && { echo yes; return; }
      ufw_state
    }
    auto_updates_linux() {
      [ -n "$(unit_field unattended-upgrades.service LoadState)" ] || { echo unknown; return; }
      [ "$(unit_field unattended-upgrades.service LoadState)" = loaded ] || { echo no; return; }
      [ "$(unit_field unattended-upgrades.service ActiveState)" = active ] || { echo no; return; }
      [ "$(unit_field unattended-upgrades.service UnitFileState)" = enabled ] || { echo no; return; }
      [ -r \#(autoUpgrades) ] || { echo unknown; return; }
      value=$(sed -n -e '/^[[:space:]]*\/\//d' -e '/^[[:space:]]*#/d' -e 's/^[[:space:]]*APT::Periodic::Unattended-Upgrade[[:space:]]*"\{0,1\}\([^";]*\).*/\1/p' \#(autoUpgrades) | head -1)
      case "$value" in ''|0) echo no ;; *) echo yes ;; esac
    }
    pending_linux() {
      command -v apt >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1 || { echo unknown; return; }
      listing=$(timeout \#(linuxPendingSeconds) apt list --upgradable 2>/dev/null) || { echo unknown; return; }
      printf '%s\n' "$listing" | grep -c -- '-security'
    }
    """#
    }

    private static let mac = #"""
    firewall_mac() {
      state=$(\#(firewallTool) --getglobalstate 2>/dev/null | sed -n 's/.*State = \([0-9]\).*/\1/p' | head -1)
      case "$state" in 0) echo no ;; 1|2) echo yes ;; *) echo unknown ;; esac
    }
    plist_flag() {
      value=$(printf '%s' "$plist" | plutil -extract "$1" raw -o - - 2>/dev/null)
      case "$value" in true|1) echo yes ;; *) echo no ;; esac
    }
    auto_updates_mac() {
      plist=$(defaults export \#(softwareUpdateDomain) - 2>/dev/null) || { echo unknown; return; }
      [ -n "$plist" ] || { echo unknown; return; }
      [ "$(plist_flag AutomaticallyInstallMacOSUpdates)" = yes ] && [ "$(plist_flag CriticalUpdateInstall)" = yes ] && { echo yes; return; }
      echo no
    }
    pending_mac() {
      command -v perl >/dev/null 2>&1 || { echo unknown; return; }
      listing=$(perl -e 'alarm shift; exec @ARGV' \#(macPendingSeconds) softwareupdate -l 2>&1) || { echo unknown; return; }
      printf '%s\n' "$listing" | grep -c '^[[:space:]]*\* Label:'
    }
    """#

    /// has_key_login: the login user has at least one public key in authorized_keys. Turning passwords off is safe only then.
    private static let main = #"""
    has_key_login() {
      file="$HOME/.ssh/authorized_keys"
      [ -e "$file" ] || { echo no; return; }
      [ -r "$file" ] || { echo unknown; return; }
      sed -e '/^[[:space:]]*#/d' "$file" | grep -Eq '(^|[[:space:]])(ssh-(ed25519|rsa|dss)|ecdsa-sha2-[a-z0-9]+|sk-[a-z0-9@.-]+) [A-Za-z0-9+/=]{20,}' && { echo yes; return; }
      echo no
    }
    case "$(uname -s)" in
      Linux)
        say password_login "$(password_login)"
        say ban_tool "$(ban_tool_linux)"
        say firewall "$(firewall_linux)"
        say auto_updates "$(auto_updates_linux)"
        say has_key_login "$(has_key_login)"
        say pending_updates "$(pending_linux)" ;;
      Darwin)
        say password_login "$(password_login)"
        say ban_tool not_available
        say firewall "$(firewall_mac)"
        say auto_updates "$(auto_updates_mac)"
        say has_key_login "$(has_key_login)"
        say pending_updates "$(pending_mac)" ;;
    esac
    exit 0
    """#
}
