#!/bin/sh
# Adds one public hostname to the MetaService Cloudflare tunnel (and its DNS record), so a far PC can download the join script over https.
# Run it on the Mac Mini, where the Cloudflare settings already are (control-plane/arm64/.env: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID,
# CLOUDFLARE_ZONE_ID; the tunnel id is read from state/cloudflared.token). Nothing secret is printed or stored.
# It changes exactly two things: one ingress rule (hostname -> local service) in the tunnel's remote configuration, and one proxied CNAME record.
# The other rules are kept as they are, and the old configuration is saved to join-share/state/ first. Safe to run again.
# Usage: sh cloudflare-hostname.sh            (dry run: shows what it would do)
#        sh cloudflare-hostname.sh --apply    (does it)
#        JOIN_HOSTNAME=join.ruvio.site JOIN_SERVICE=http://127.0.0.1:9110 sh cloudflare-hostname.sh --apply
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
ARM64="${PARENT_DIR:-$HOME/MetaService/control-plane/arm64}"
HOSTNAME_WANTED="${JOIN_HOSTNAME:-join.ruvio.site}"
SERVICE_WANTED="${JOIN_SERVICE:-http://127.0.0.1:9110}"
API=https://api.cloudflare.com/client/v4
APPLY=no
[ "${1:-}" = --apply ] && APPLY=yes

say() { printf '%s\n' "$*"; }
value() { grep -h "^$1=" "$ARM64/.env" | head -1 | cut -d= -f2- | tr -d '"'"'"; }

TOKEN=$(value CLOUDFLARE_API_TOKEN); ACCOUNT=$(value CLOUDFLARE_ACCOUNT_ID); ZONE=$(value CLOUDFLARE_ZONE_ID)
[ -n "$TOKEN" ] && [ -n "$ACCOUNT" ] && [ -n "$ZONE" ] || { say "the Cloudflare settings are not all in $ARM64/.env"; exit 1; }
TUNNEL=$(python3 - "$ARM64/state/cloudflared.token" <<'PY'
import base64, json, sys
raw = open(sys.argv[1]).read().strip()
raw += "=" * (-len(raw) % 4)
print(json.loads(base64.b64decode(raw))["t"])
PY
)
[ -n "$TUNNEL" ] || { say "could not read the tunnel id from cloudflared.token"; exit 1; }

# The token goes to curl through a config file on stdin, never on a command line (a command line shows in `ps`).
call() {
  method=$1; path=$2; body=${3:-}
  if [ -n "$body" ]; then
    printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "$TOKEN" | curl -sS -m 30 -K - -X "$method" "$API$path" --data "$body"
  else
    printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS -m 30 -K - -X "$method" "$API$path"
  fi
}
field() { python3 -c "import sys,json; d=json.load(sys.stdin); print(d$1)" 2>/dev/null; }

say "== the tunnel"
INFO=$(call GET "/accounts/$ACCOUNT/cfd_tunnel/$TUNNEL")
[ "$(printf '%s' "$INFO" | field "['success']")" = True ] || { say "Cloudflare refused: $(printf '%s' "$INFO" | field "['errors']")"; exit 1; }
say "name: $(printf '%s' "$INFO" | field "['result']['name']"), managed: $(printf '%s' "$INFO" | field "['result']['config_src']")"
[ "$(printf '%s' "$INFO" | field "['result']['config_src']")" = cloudflare ] || { say "this tunnel is configured by a local file, not remotely; add the hostname in that file instead"; exit 1; }

say "== its rules now"
CONFIG=$(call GET "/accounts/$ACCOUNT/cfd_tunnel/$TUNNEL/configurations")
[ "$(printf '%s' "$CONFIG" | field "['success']")" = True ] || { say "could not read the configuration: $(printf '%s' "$CONFIG" | field "['errors']")"; exit 1; }
printf '%s' "$CONFIG" | python3 -c "
import sys, json
for rule in json.load(sys.stdin)['result']['config']['ingress']:
    print('  ', rule.get('hostname', '(any other)'), '->', rule['service'])"

NEW=$(printf '%s' "$CONFIG" | python3 -c "
import sys, json
host, service = sys.argv[1], sys.argv[2]
config = json.load(sys.stdin)['result']['config']
rules = [r for r in config['ingress'] if r.get('hostname') != host]
catch_all = [r for r in rules if 'hostname' not in r]
named = [r for r in rules if 'hostname' in r]
config['ingress'] = named + [{'hostname': host, 'service': service}] + (catch_all or [{'service': 'http_status:404'}])
print(json.dumps({'config': config}))" "$HOSTNAME_WANTED" "$SERVICE_WANTED")

say "== the change"
say "  + $HOSTNAME_WANTED -> $SERVICE_WANTED (the other rules stay)"
say "  + DNS: $HOSTNAME_WANTED CNAME $TUNNEL.cfargotunnel.com (proxied), if it does not exist"
if [ "$APPLY" != yes ]; then say "dry run: nothing changed. Run again with --apply."; exit 0; fi

mkdir -p "$HERE/state"
BACKUP="$HERE/state/cloudflare-ingress-before-$(date +%Y%m%d-%H%M%S).json"
printf '%s' "$CONFIG" > "$BACKUP"; chmod 600 "$BACKUP"
say "saved the old configuration to $BACKUP"

RESULT=$(call PUT "/accounts/$ACCOUNT/cfd_tunnel/$TUNNEL/configurations" "$NEW")
[ "$(printf '%s' "$RESULT" | field "['success']")" = True ] || { say "Cloudflare refused the new rules: $(printf '%s' "$RESULT" | field "['errors']")"; exit 1; }
say "tunnel rules updated"

EXISTING=$(call GET "/zones/$ZONE/dns_records?type=CNAME&name=$HOSTNAME_WANTED")
if [ "$(printf '%s' "$EXISTING" | field "['result_info']['count']")" != 0 ]; then
  say "DNS record already exists"
else
  RECORD=$(call POST "/zones/$ZONE/dns_records" "{\"type\":\"CNAME\",\"name\":\"$HOSTNAME_WANTED\",\"content\":\"$TUNNEL.cfargotunnel.com\",\"proxied\":true}")
  [ "$(printf '%s' "$RECORD" | field "['success']")" = True ] || { say "Cloudflare refused the DNS record: $(printf '%s' "$RECORD" | field "['errors']")"; exit 1; }
  say "DNS record created"
fi
say "done: https://$HOSTNAME_WANTED/ now reaches $SERVICE_WANTED (give it up to a minute)"
