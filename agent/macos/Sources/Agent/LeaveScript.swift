import Foundation

/// The clean-up the helper runs when the admin removes this computer in the panel and asks for it to be cleaned. It is `agent/linux/src/leave-from-panel.sh`, copied
/// here because a Swift package cannot embed a file from outside it; a test compares the two, so they cannot drift apart.
enum LeaveScript {
    static let text = #"""
#!/bin/sh
# Run by the MetaService helper (it is built into the helper) when the admin removes this computer in the panel and asks for it to be cleaned.
# Does what $HOME/.metaservice-join/leave.sh does, with no terminal: the sudo password arrives as the first line of standard input, is used once, and is never stored.
# Order matters: the root step comes first and prints one marker line, so a wrong password changes nothing; only after "ms-leave: root-ok" is anything of the join deleted.
# Usage: leave-from-panel.sh <join home>   (stdin: the sudo password, or an empty line when no password is needed)
trap '' PIPE
JOIN_HOME=${1:-}
SUDO_BIN=${MS_LEAVE_SUDO:-sudo}

fail() { echo "ms-leave: $1"; exit 1; }

[ -n "$JOIN_HOME" ] && [ -f "$JOIN_HOME/joined.env" ] || fail "not-joined"
# shellcheck disable=SC1090,SC1091
. "$JOIN_HOME/joined.env" || fail "unreadable"
IFS= read -r PW || PW=""

case "$MS_OS-$MS_BOOT" in
  mac-*) ROOT="wg-quick down '$MS_CONF' || true; rm -f '$MS_CONF' '$MS_WG_PLIST'" ;;
  linux-systemd) ROOT="systemctl disable --now 'wg-quick@$MS_IFACE' || true; rm -f '$MS_CONF'" ;;
  *) ROOT="wg-quick down '$MS_CONF' || true; rm -f '$MS_CONF'" ;;
esac

# The WireGuard interface is this conversation's road home: taking it down also kills the answer the
# panel is waiting for. The sudo front (verify the password) runs in the foreground; the teardown itself
# is backgrounded so the helper can answer over the still-alive tunnel first. Wrong password still
# changes nothing: a refused password fails before any backgrounding.
DELAY_BEFORE_TEARDOWN=12

# The root step. As root already nothing is asked; otherwise sudo reads the password from this pipe (-S, empty prompt) or never asks (-n) when none was given.
if [ "${MS_UID:-1}" = 0 ]; then
  sh -c "sleep $DELAY_BEFORE_TEARDOWN; $ROOT" >/dev/null 2>&1 & 
  sleep 1
  kill -0 $! 2>/dev/null || fail "root-failed: the WireGuard clean-up did not work"
elif [ -n "$PW" ]; then
  printf '%s\n' "$PW" | "$SUDO_BIN" -S -p '' -b sh -c "sleep $DELAY_BEFORE_TEARDOWN; PATH='$PATH'; export PATH; $ROOT" >/dev/null 2>&1 || fail "root-failed: sudo did not accept the password, or this login may not use sudo"
else
  "$SUDO_BIN" -n -b sh -c "sleep $DELAY_BEFORE_TEARDOWN; PATH='$PATH'; export PATH; $ROOT" >/dev/null 2>&1 || fail "root-failed: sudo needs a password and none was typed"
fi
PW=""
echo "ms-leave: root-ok"

# From here the helper may already be gone, so nothing is printed any more. A short wait lets the helper answer the panel first.
exec >/dev/null 2>&1
sleep 2
PID=""
[ ! -f "$MS_HOME/state/agent.pid" ] || PID=$(cat "$MS_HOME/state/agent.pid" 2>/dev/null)
if [ "$MS_OS" = linux ] && [ -n "$MS_UNIT" ]; then systemctl --user disable "$MS_LABEL.service"; fi
[ -z "$MS_UNIT" ] || rm -f "$MS_UNIT"
rm -rf "$MS_HOME"
# The last steps stop the helper, which may stop this script too (it lives in the helper's service), so everything above is already done.
if [ "$MS_OS" = linux ] && [ -n "$MS_UNIT" ]; then
  systemctl --user daemon-reload
  systemctl --user stop "$MS_LABEL.service"
elif [ "$MS_OS" = mac ]; then
  launchctl bootout "gui/$MS_UID/$MS_LABEL"
fi
[ -z "$PID" ] || kill "$PID"
exit 0
"""#
}
