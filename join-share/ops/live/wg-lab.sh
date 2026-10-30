#!/bin/sh
# The live network test of join-share, run on the Mac Mini only (needs `sudo -n`, the Homebrew WireGuard tools and Apple's `container`).
# Two throw-away Linux containers (jstest-a, jstest-b) play two far PCs. The Mini plays the hub, on a lab interface and a lab port, so nothing
# of the real hub or of MAAS is touched. It proves, with real WireGuard and the real pf rules:
#   1. both spokes handshake with the hub and the hub reaches each spoke's helper port;
#   2. a spoke reaches only TCP 10.77.0.1:9102 on the hub, and that port reaches the parent's loopback listener with the spoke's own address as the source;
#   3. a spoke cannot reach the other spoke, and cannot reach any other port of the hub (the panel, ssh, MAAS).
# Usage: sh wg-lab.sh        (prints PASS / FAIL per check, then removes everything it made; exit 1 if any check failed)
set -u

export PATH=/opt/homebrew/bin:$PATH
LAB="${LAB_DIR:-$HOME/join-share-logs/lab}"
IFACE_NAME=wg-lab
HUB_ADDR=10.77.0.1
SPOKE_A=10.77.0.2
SPOKE_B=10.77.0.3
WG_PORT=51839
PARENT_PORT=9102
HELPER_PORT=9101
OTHER_PORT=9777
ANCHOR=com.metaservice.joinshare.lab
FAILED=0
LISTEN_PIDS=""

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=1; }
check() { if [ "$2" = "yes" ]; then pass "$1"; else fail "$1"; fi; }
yesno() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
blocked() { if [ "$1" = no ]; then echo yes; else echo no; fi; }

cleanup() {
  sudo -n pfctl -a "$ANCHOR" -F all >/dev/null 2>&1
  sudo -n pfctl -f /etc/pf.conf >/dev/null 2>&1
  if [ -n "${PF_WAS_OFF:-}" ]; then sudo -n pfctl -d >/dev/null 2>&1; fi
  sudo -n env PATH="$PATH" wg-quick down "$LAB/$IFACE_NAME.conf" >/dev/null 2>&1
  for name in jstest-a jstest-b; do container stop "$name" >/dev/null 2>&1; done
  if [ -n "$LISTEN_PIDS" ]; then kill $LISTEN_PIDS >/dev/null 2>&1; fi
  true
}
trap cleanup EXIT INT TERM

mkdir -p "$LAB" && chmod 700 "$LAB"
umask 077
: > "$LAB/parent.seen"

# The Mini's address on the container network: the .1 of the default network.
HUB_HOST=$(container network list 2>/dev/null | awk '$1=="default"{print $2}' | sed 's#\.[0-9]*/.*#.1#')
[ -n "$HUB_HOST" ] || { echo "cannot find the container network"; exit 2; }

key_pair() { wg genkey | tee "$LAB/$1.key" | wg pubkey > "$LAB/$1.pub"; }
key_pair hub; key_pair a; key_pair b

cat > "$LAB/$IFACE_NAME.conf" <<EOF
[Interface]
PrivateKey = $(cat "$LAB/hub.key")
Address = $HUB_ADDR/24
ListenPort = $WG_PORT

[Peer]
PublicKey = $(cat "$LAB/a.pub")
AllowedIPs = $SPOKE_A/32

[Peer]
PublicKey = $(cat "$LAB/b.pub")
AllowedIPs = $SPOKE_B/32
EOF

sudo -n env PATH="$PATH" wg-quick up "$LAB/$IFACE_NAME.conf" >"$LAB/up.log" 2>&1 || { cat "$LAB/up.log"; exit 2; }
# /var/run/wireguard is root-only, so the real interface name comes from wg-quick's own output.
HUB_IF=$(sed -n 's/.*Interface for .* is \(utun[0-9]*\).*/\1/p' "$LAB/up.log")
[ -n "$HUB_IF" ] || { echo "no interface name"; exit 2; }
echo "hub interface $HUB_IF, the Mini on the container network is $HUB_HOST"

# pf ignores an anchor that nothing refers to, so the active ruleset becomes /etc/pf.conf plus two lines: our rdr-anchor right after Apple's
# rdr-anchor and our filter anchor right after Apple's anchor. /etc/pf.conf itself is never edited; cleanup reloads it.
cat > "$LAB/anchor.rules" <<EOF
rdr pass on $HUB_IF inet proto tcp from any to $HUB_ADDR port $PARENT_PORT -> 127.0.0.1 port $PARENT_PORT
block in quick on $HUB_IF all
pass out quick on $HUB_IF all
EOF
awk -v a="$ANCHOR" '{print} /^rdr-anchor "com.apple\/\*"/{print "rdr-anchor \"" a "\""} /^anchor "com.apple\/\*"/{print "anchor \"" a "\""}' /etc/pf.conf > "$LAB/pf.main"
if sudo -n pfctl -s info 2>/dev/null | grep -q "Status: Disabled"; then PF_WAS_OFF=1; fi
sudo -n pfctl -f "$LAB/pf.main" >"$LAB/pf.log" 2>&1 || { cat "$LAB/pf.log"; exit 2; }
if [ -n "${PF_WAS_OFF:-}" ]; then sudo -n pfctl -e >>"$LAB/pf.log" 2>&1; fi
sudo -n pfctl -a "$ANCHOR" -f "$LAB/anchor.rules" >>"$LAB/pf.log" 2>&1 || { cat "$LAB/pf.log"; exit 2; }

# The two spokes: Ubuntu containers with network admin (WireGuard here is wireguard-go: the container kernel has no WireGuard). They are made once,
# kept between runs (cleanup only stops them), and only ever named jstest-*; nothing else on the Mini's container system is touched.
ensure_spoke() {
  if container list --all 2>/dev/null | grep -q "^$1 "; then container start "$1" >/dev/null 2>&1
  else container run -d --name "$1" --cap-add CAP_NET_ADMIN ubuntu:24.04 sleep infinity >/dev/null 2>&1; fi
  sleep 2
  if container exec "$1" sh -c 'command -v wg-quick && command -v wireguard-go && command -v nc' >/dev/null 2>&1; then return 0; fi
  container exec "$1" sh -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard-tools wireguard-go iproute2 iputils-ping netcat-openbsd' >/dev/null 2>&1
}
ensure_spoke jstest-a
ensure_spoke jstest-b
spoke_conf() {
  cat <<EOF
[Interface]
PrivateKey = $(cat "$LAB/$1.key")
Address = $2/32

[Peer]
PublicKey = $(cat "$LAB/hub.pub")
Endpoint = $HUB_HOST:$WG_PORT
AllowedIPs = $HUB_ADDR/32
PersistentKeepalive = 5
EOF
}
start_spoke() {
  spoke_conf "$2" "$3" | container exec -i "$1" sh -c "mkdir -p /etc/wireguard && cat > /etc/wireguard/wg-lab.conf && chmod 600 /etc/wireguard/wg-lab.conf && wg-quick up wg-lab" >"$LAB/spoke-$2.log" 2>&1
}
start_spoke jstest-a a "$SPOKE_A"
start_spoke jstest-b b "$SPOKE_B"
sleep 3

# Listeners: the parent's stand-in on the Mini's loopback (it records who connected), another port on all interfaces, a helper stand-in in spoke A.
cat > "$LAB/parent.py" <<EOF
import http.server, sys
seen = sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        open(seen, "a").write(self.client_address[0] + "\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"parent")
    def log_message(self, *args): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
EOF
python3 "$LAB/parent.py" "$PARENT_PORT" "$LAB/parent.seen" &
LISTEN_PIDS="$!"
python3 -m http.server "$OTHER_PORT" --bind 0.0.0.0 >/dev/null 2>&1 &
LISTEN_PIDS="$LISTEN_PIDS $!"
container exec -d jstest-a sh -c "while true; do echo helper | nc -l -p $HELPER_PORT -q 1; done"
sleep 2

tcp_from() { container exec "$1" sh -c "nc -z -w 3 $2 $3" >/dev/null 2>&1 && echo yes || echo no; }

handshakes=$(sudo -n env PATH="$PATH" wg show "$HUB_IF" latest-handshakes 2>/dev/null | awk '$2>0' | wc -l | tr -d ' ')
check "both spokes completed a handshake with the hub ($handshakes of 2)" "$([ "$handshakes" = 2 ] && echo yes || echo no)"
check "the hub reaches spoke A's helper port over the tunnel" "$(yesno nc -z -w 3 "$SPOKE_A" "$HELPER_PORT")"
check "spoke A reaches the hub's parent port $PARENT_PORT" "$(tcp_from jstest-a "$HUB_ADDR" "$PARENT_PORT")"
reply=$(container exec jstest-b sh -c "printf 'GET / HTTP/1.0\\r\\n\\r\\n' | nc -w 3 $HUB_ADDR $PARENT_PORT" 2>/dev/null | tail -1)
check "the parent's listener answers through the redirect" "$([ "$reply" = parent ] && echo yes || echo no)"
check "the parent saw spoke B's own address as the source, not loopback" "$(yesno grep -qx "$SPOKE_B" "$LAB/parent.seen")"
check "spoke A cannot reach spoke B" "$(blocked "$(tcp_from jstest-a "$SPOKE_B" "$HELPER_PORT")")"
check "spoke A cannot reach another port on the hub address ($OTHER_PORT)" "$(blocked "$(tcp_from jstest-a "$HUB_ADDR" "$OTHER_PORT")")"
check "spoke A cannot reach the hub's ssh port (22)" "$(blocked "$(tcp_from jstest-a "$HUB_ADDR" 22)")"
check "spoke A cannot reach the Mini's loopback panel port (9100) through the hub address" "$(blocked "$(tcp_from jstest-a "$HUB_ADDR" 9100)")"
check "the lab port is open from the Mini itself (so the block above is the firewall, not a dead listener)" "$(yesno nc -z -w 3 127.0.0.1 "$OTHER_PORT")"

exit $FAILED
