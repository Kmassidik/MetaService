import Foundation

/// Who owns the helper process on the other computer, and the shell the update script uses to stop and start it under that owner.
///
/// Why: when the helper is registered to start by itself (a systemd user unit on Linux, a LaunchAgent on a Mac), a helper started by `start.sh` is a second owner. The
/// next restart of the computer starts the unit while an old `start.sh` process may still hold the port, and `autostart status` reports `running_by_systemd: false`.
/// So when the registration is in force, the update stops and starts the helper through it; `start.sh` stays for a computer without it (no unit, no linger, no LaunchAgent).
///
/// A Mac helper is restarted by unloading and loading its LaunchAgent (bootout, bootstrap), never with `kickstart`: since macOS 27 (found 2026-11-14) launchd pins a login-loaded
/// background item to the exact build, and the first `kickstart` of a replaced build is killed ("Launch Constraint Violation"); a job loaded by bootstrap carries no such pin.
///
/// There is deliberately no fallback from the owner to `start.sh` when the owner's start fails: the unit would retry on its own and two helpers would fight for the port.
/// A failed start reads as "did not answer", which is the rollback.
enum HelperUpdateOwner {
    static let unitName = "metaservice-agent.service"
    static let launchAgentLabel = "io.metaservice.agent"
    /// How long the update waits for launchd to forget the old job before it loads the job again.
    static let launchdUnloadSeconds = 20
    /// Pauses (seconds) between the attempts to load the job again.
    static let launchdLoadPauses = "1 2 4 8"
    /// What `autostart status` prints when everything works after a reboot (a unit that is enabled and lingering).
    static let effectiveMarker = #""effective":true"#

    /// Shell for the update script, after `cd "$box"`: it sets `owner` (systemd, launchd or script) from the OLD program, before anything is stopped,
    /// and defines `halt` and `launch`, which the replacement and the rollback both use, so both end under the same owner.
    static let lines = #"""
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
    owner=script
    if [ "$(uname -s)" = Darwin ]; then
      launchctl print "gui/$(id -u)/\#(launchAgentLabel)" >/dev/null 2>&1 && owner=launchd
    else
      ./bin/metaservice-agent autostart status --box "$box" 2>/dev/null | grep -q '\#(effectiveMarker)' && owner=systemd
    fi
    halt() {
      [ "$owner" != systemd ] || systemctl --user stop \#(unitName) >/dev/null 2>&1 || true
      [ ! -x ./stop.sh ] || sh ./stop.sh
    }
    launchd_start() {
      uid=$(id -u); target="gui/$uid/\#(launchAgentLabel)"; plist="$HOME/Library/LaunchAgents/\#(launchAgentLabel).plist"
      [ -f "$plist" ] || { launchctl kickstart -k "$target" >/dev/null 2>&1; return; }
      launchctl bootout "$target" >/dev/null 2>&1 || true
      gone=0
      while launchctl print "$target" >/dev/null 2>&1 && [ "$gone" -lt \#(launchdUnloadSeconds) ]; do sleep 1; gone=$((gone + 1)); done
      for pause in \#(launchdLoadPauses); do
        launchctl bootstrap "gui/$uid" "$plist" >/dev/null 2>&1 && break
        sleep "$pause"
      done
      launchctl print "$target" >/dev/null 2>&1 || launchctl load -w "$plist" >/dev/null 2>&1 || true
      launchctl print "$target" >/dev/null 2>&1 || launchctl kickstart -k "$target" >/dev/null 2>&1 || true
    }
    launch() {
      [ "$owner" != systemd ] || { systemctl --user restart \#(unitName) >/dev/null 2>&1; return; }
      [ "$owner" != launchd ] || { launchd_start; return; }
      sh ./start.sh >/dev/null 2>&1 || true
    }
    """#
}
