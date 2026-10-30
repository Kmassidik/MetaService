#!/bin/sh
# Opens the join-share admin page on this Mac with one double-click: it opens the SSH forward to the Mini, reads the admin key from the Mini and puts it
# in the address after `#`, so it is never typed and never sent to a server. Keep this window open while you use the page; closing it closes the forward.
# Settings (optional): JOIN_SHARE_SSH_HOST (default macmini), JOIN_SHARE_ADMIN_LOCAL_PORT (default 9111).
set -eu

HOST="${JOIN_SHARE_SSH_HOST:-macmini}"
PORT="${JOIN_SHARE_ADMIN_LOCAL_PORT:-9111}"
KEY_FILE='~/MetaService/join-share/state/admin.key'

KEY=$(ssh "$HOST" "cat $KEY_FILE")
[ -n "$KEY" ] || { echo "could not read the admin key on $HOST"; exit 1; }
ssh -N -L "$PORT:127.0.0.1:9111" "$HOST" &
FORWARD=$!
trap 'kill $FORWARD 2>/dev/null' EXIT INT TERM
sleep 2
open "http://127.0.0.1:$PORT/#key=$KEY"
echo "The join admin page is open in your browser."
echo "Keep this window open while you use it. Close it (or press Ctrl-C) to close the connection."
wait $FORWARD
