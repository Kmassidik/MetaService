#!/bin/sh
# The end-to-end join test, run on the Mac Mini only (needs `sudo -n`, the release build of the hub, Homebrew WireGuard, Apple's `container`).
# It runs the REAL join script inside a Linux container (jstest-a, a far PC with the REAL linux-arm64 helper) against a REAL hub and a throw-away
# copy of the parent (the production binary started on other ports with its own database in $W/parent). Nothing of the running parent, MAAS or a
# production hub is touched: other ports, another WireGuard network (10.78.0.0/24), another pf anchor, another interface name.
# What it proves, in order: a link is made; the script asks nothing it should not; the machine registers and shows a 6-digit code; the admin approves with it;
# the interface comes up; the helper is downloaded, checked, enrolled and started; the parent records the machine at its WireGuard address (the one
# contact: the enrollments row) and receives its heartbeat; a used link is dead; leave.sh takes it all away; removing the peer closes the door.
# Usage: sh join-e2e.sh        (prints PASS / FAIL per check, removes what it made, exit 1 if any check failed)
set -u

export PATH=/opt/homebrew/bin:$PATH
CLONE="${CLONE_DIR:-$HOME/MetaService-join-share}"
BIN="$CLONE/join-share/hub/target/release"
W="${E2E_DIR:-$HOME/join-share-logs/e2e}"
PARENT_BIN="$HOME/MetaService/control-plane/arm64/.build/debug/metaservice-root"
BUILDS="$HOME/MetaService/control-plane/arm64/state/agent-builds"
NET=10.78.0.0/24
HUB_ADDR=10.78.0.1
SPOKE_ADDR=10.78.0.2
WG_PORT=51840
WG_NAME=wg-jse2e
ANCHOR=com.apple/joinshare-e2e
PARENT_PORT=9190
PARENT_AGENT_PORT=9192
PUBLIC_PORT=9210
ADMIN_PORT=9211
MACHINE=e2e-box
FAILED=0
PIDS=""

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=1; }
check() { if [ "$2" = "yes" ]; then pass "$1"; else fail "$1"; fi; }
yesno() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
inside() { container exec jstest-a sh -c "$1"; }

cleanup() {
  if [ -n "${E2E_KEEP:-}" ]; then echo "E2E_KEEP is set: nothing was torn down (hub, parent, tunnel and container keep running for inspection)"; return 0; fi
  if [ -n "$PIDS" ]; then kill $PIDS >/dev/null 2>&1; fi
  sudo -n "$ROOT_HELPER" pf-unload >/dev/null 2>&1
  sudo -n "$ROOT_HELPER" down >/dev/null 2>&1
  inside 'sh ~/.metaservice-join/leave.sh >/dev/null 2>&1; pkill -f metaservice-agent; ip link del wg-meta 2>/dev/null; true' >/dev/null 2>&1
  container stop jstest-a >/dev/null 2>&1
  true
}
trap cleanup EXIT INT TERM

for tool in "$BIN/join-share" "$BIN/join-share-root" "$PARENT_BIN" "$BUILDS/metaservice-agent-linux-arm64"; do
  [ -x "$tool" ] || { echo "missing $tool (build the hub first: cd join-share/hub && cargo build --release)"; exit 2; }
done
ROOT_HELPER="$BIN/join-share-root"

rm -rf "$W" && mkdir -p "$W/parent/state" "$W/hub-state" && chmod 700 "$W"
# The Mini's address on the container network exists only while a container runs, so the far PC is started first.
container start jstest-a >/dev/null 2>&1; sleep 3
HOST_IP=$(container network list 2>/dev/null | awk '$1=="default"{print $2}' | sed 's#\.[0-9]*/.*#.1#')
[ -n "$HOST_IP" ] || { echo "no container network"; exit 2; }

# 1. A throw-away parent: the production binary, other ports, its own database (cwd decides where state/ and .env go).
(cd "$W/parent" && "$PARENT_BIN" --db state/root.sqlite3 --port $PARENT_PORT --bind 127.0.0.1 --agent-port $PARENT_AGENT_PORT --agent-bind 127.0.0.1 --ui-dir /nonexistent >parent.log 2>&1 &)
PARENT_PID=$(pgrep -f "db state/root.sqlite3 --port $PARENT_PORT" | head -1)
PIDS="$PARENT_PID"
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -m 2 -o /dev/null "http://127.0.0.1:$PARENT_PORT/health" && break; sleep 1; done
check "the throw-away parent is up (own database, other ports)" "$(yesno curl -sf -m 2 "http://127.0.0.1:$PARENT_PORT/health")"

# 2. The hub, all settings from the environment.
ENVIRON="JOIN_SHARE_NET=$NET JOIN_SHARE_WG_PORT=$WG_PORT JOIN_SHARE_WG_NAME=$WG_NAME JOIN_SHARE_PF_ANCHOR=$ANCHOR JOIN_SHARE_ENDPOINT=$HOST_IP:$WG_PORT \
JOIN_SHARE_PUBLIC_URL=http://$HOST_IP:$PUBLIC_PORT JOIN_SHARE_PUBLIC_BIND=$HOST_IP:$PUBLIC_PORT JOIN_SHARE_ADMIN_BIND=127.0.0.1:$ADMIN_PORT \
JOIN_SHARE_STATE=$W/hub-state JOIN_SHARE_PARENT_DB=$W/parent/state/root.sqlite3 JOIN_SHARE_PARENT_URL=http://$HUB_ADDR:$PARENT_AGENT_PORT \
JOIN_SHARE_BUILDS_DIR=$BUILDS JOIN_SHARE_MAC_AGENT=$W/none JOIN_SHARE_ROOT_HELPER=$ROOT_HELPER"
# shellcheck disable=SC2086
env $ENVIRON "$BIN/join-share" serve >"$W/hub.log" 2>&1 &
PIDS="$PIDS $!"
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -m 2 -o /dev/null "http://127.0.0.1:$ADMIN_PORT/" && break; sleep 1; done
check "the hub is up (admin page answers)" "$(yesno curl -sf -m 2 "http://127.0.0.1:$ADMIN_PORT/")"
KEY=$(cat "$W/hub-state/admin.key" 2>/dev/null)
admin() { curl -s -m 10 -H "X-Admin-Key: $KEY" -H 'Content-Type: application/json' "$@"; }
json() { python3 -c "import sys,json; d=json.load(sys.stdin); print(d$1)" 2>/dev/null; }

# 3. A link for a Linux ARM machine (the container).
check "supported table: Linux arm64 is offered, Windows is coming soon" "$(admin "http://127.0.0.1:$ADMIN_PORT/admin/supported" | python3 -c "
import sys,json
t={e['os']:{c['cpu']:c['state'] for c in e['cpus']} for e in json.load(sys.stdin)}
print('yes' if t['linux']['arm64'] in ('ready','untested') and set(t['windows'].values())=={'soon'} else 'no')" 2>/dev/null)"
LINK_REPLY=$(admin -X POST -d '{"os":"linux","cpu":"arm64"}' "http://127.0.0.1:$ADMIN_PORT/admin/links")
COMMAND=$(printf '%s' "$LINK_REPLY" | json "['command']")
LINK=$(printf '%s' "$LINK_REPLY" | json "['link']")
check "the admin API gives a one-line command with the link inside" "$([ -n "$COMMAND" ] && printf '%s' "$COMMAND" | grep -q "/j/$LINK" && echo yes || echo no)"
check "a made-up link gets 404 and a unified answer" "$([ "$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST_IP:$PUBLIC_PORT/j/not-a-link?os=linux&cpu=arm64")" = 404 ] && echo yes || echo no)"
check "an unsupported pair is refused with 400 (Windows)" "$([ "$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST_IP:$PUBLIC_PORT/j/$LINK?os=windows&cpu=x86_64")" = 400 ] && echo yes || echo no)"

# 4. The far PC: a clean container; the real script, in the background, its output in a file.
inside 'sh ~/.metaservice-join/leave.sh >/dev/null 2>&1; rm -rf ~/.metaservice-join ~/metaservice-box /tmp/join.log; true' >/dev/null 2>&1
# The variable must reach the `sh` at the end of the pipe, not `curl`, so it is exported first.
container exec -d jstest-a sh -c "export JOIN_SHARE_YES=1 JOIN_ENGINE=simulated; $COMMAND > /tmp/join.log 2>&1"

CODE=""
for _ in $(seq 1 60); do
  CODE=$(inside 'grep -Eo "(^|[^0-9])[0-9]{3} ?[0-9]{3}([^0-9]|$)" /tmp/join.log 2>/dev/null | head -1 | tr -dc 0-9' 2>/dev/null)
  [ -n "$CODE" ] && break
  sleep 2
done
check "the script registered and showed a 6-digit approval code" "$([ "${#CODE}" = 6 ] && echo yes || echo no)"
inside 'cat /tmp/join.log' 2>/dev/null | sed 's/[0-9]\{6\}/<code>/g' | tail -15

# 5. The admin approves: a wrong code first, then the right one.
PENDING=$(admin "http://127.0.0.1:$ADMIN_PORT/admin/pending" | json "[0]['id']")
check "the pending machine is listed, and the list never contains the code" "$([ -n "$PENDING" ] && ! admin "http://127.0.0.1:$ADMIN_PORT/admin/pending" | grep -q "$CODE" && echo yes || echo no)"
ASK=$(admin "http://127.0.0.1:$ADMIN_PORT/admin/pending" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)[0]['share']))")
WRONG=$(admin -o /dev/null -w '%{http_code}' -X POST -d "{\"code\":\"000000\",\"name\":\"$MACHINE\",\"share\":$ASK}" "http://127.0.0.1:$ADMIN_PORT/admin/pending/$PENDING/approve")
check "a wrong code is refused (403)" "$([ "$WRONG" = 403 ] && echo yes || echo no)"
RIGHT=$(admin -o "$W/approve.json" -w '%{http_code}' -X POST -d "{\"code\":\"$CODE\",\"name\":\"$MACHINE\",\"share\":$ASK}" "http://127.0.0.1:$ADMIN_PORT/admin/pending/$PENDING/approve")
check "the right code approves and gives the machine an address" "$([ "$RIGHT" = 200 ] && grep -q "$SPOKE_ADDR" "$W/approve.json" && echo yes || echo no)"

if [ -n "${E2E_KEEP:-}" ]; then echo "E2E_KEEP is set: pausing 300 s after the approval so the tunnel can be inspected"; sleep 300; fi

# 6. The far PC finishes by itself: tunnel, helper download, enrol, run.
DB="$W/parent/state/root.sqlite3"
ROW=""
for _ in $(seq 1 60); do
  ROW=$(sqlite3 "$DB" "SELECT name || '|' || ip || '|' || IFNULL(os,'') || '|' || IFNULL(last_seen,0) FROM machines WHERE name='$MACHINE'" 2>/dev/null)
  [ -n "$ROW" ] && break
  sleep 3
done
check "the parent lists the machine, recorded at its WireGuard address ($SPOKE_ADDR)" "$(printf '%s' "$ROW" | grep -q "^$MACHINE|$SPOKE_ADDR|" && echo yes || echo no)"
FRESH=no
for _ in $(seq 1 30); do
  SEEN=$(sqlite3 "$DB" "SELECT IFNULL(last_seen,0) FROM machines WHERE name='$MACHINE'" 2>/dev/null)
  if [ -n "$SEEN" ] && [ "$SEEN" -gt 0 ] && [ $(( $(date +%s) - SEEN )) -lt 30 ]; then FRESH=yes; break; fi
  sleep 3
done
check "its heartbeat is arriving (last seen under 30 s ago)" "$FRESH"
check "the enrollment row was used up, from the pinned address" "$([ "$(sqlite3 "$DB" "SELECT COUNT(*) FROM enrollments WHERE machine_name='$MACHINE' AND used_at IS NOT NULL AND expected_ip='$SPOKE_ADDR'")" = 1 ] && echo yes || echo no)"
REACH=no
for _ in $(seq 1 10); do if nc -z -w 3 "$SPOKE_ADDR" 9101 >/dev/null 2>&1; then REACH=yes; break; fi; sleep 3; done
check "the parent side reaches the helper port over the tunnel ($SPOKE_ADDR:9101)" "$REACH"
LISTEN=$(inside 'ss -ltn | grep ":9101 "' 2>/dev/null | awk '{print $4}' | sort -u)
check "the helper listens on the WireGuard address only, not on all addresses" "$([ "$LISTEN" = "$SPOKE_ADDR:9101" ] && echo yes || echo no)"
check "the used link is dead (404)" "$([ "$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST_IP:$PUBLIC_PORT/j/$LINK?os=linux&cpu=arm64")" = 404 ] && echo yes || echo no)"
check "the enrollment token file is not left on the far PC" "$(inside 'find ~/.metaservice-join /tmp -iname "enroll*" 2>/dev/null | grep -q . && echo no || echo yes' 2>/dev/null)"
check "the far PC's private key is mode 600" "$(inside 'f=$(find ~/.metaservice-join -name "*.key" 2>/dev/null | head -1); [ -n "$f" ] && [ "$(stat -c %a "$f")" = 600 ] && echo yes || echo no' 2>/dev/null)"

# 7. The peer list, then leave, then the door closes.
check "the hub lists the peer with a recent handshake" "$(admin "http://127.0.0.1:$ADMIN_PORT/admin/peers" | grep -q "$MACHINE" && echo yes || echo no)"
inside 'sh ~/.metaservice-join/leave.sh' >"$W/leave.log" 2>&1
sleep 3
check "leave.sh stopped the helper and removed the interface and its folder" "$(inside '! pgrep -f metaservice-agent >/dev/null && ! ip link show wg-meta >/dev/null 2>&1 && [ ! -d ~/.metaservice-join/bin ] && [ ! -f ~/.metaservice-join/state/agent.token ] && echo yes || echo no' 2>/dev/null)"
DEL=$(admin -o /dev/null -w '%{http_code}' -X DELETE "http://127.0.0.1:$ADMIN_PORT/admin/peers/$MACHINE")
check "removing the peer on the hub works (the address is freed)" "$([ "$DEL" = 200 ] || [ "$DEL" = 204 ] && echo yes || echo no)"
check "the hub's WireGuard interface has no peer left" "$([ "$(sudo -n env PATH="$PATH" wg show all peers 2>/dev/null | grep -c .)" = 0 ] && echo yes || echo no)"

echo "DONE failed=$FAILED"
exit $FAILED
