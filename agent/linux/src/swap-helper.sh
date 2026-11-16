#!/bin/sh
# Swaps this computer's helper for the one the panel just sent, restarts the boot entry, and puts the old file back if the new helper does not come up.
# Started by the helper itself (see self_update.rs) outside its own process group. Usage: swap-helper.sh <new file> <installed file> <unit label> <settle seconds>
NEW=$1
OWN=$2
LABEL=$3
SETTLE=${4:-25}
OLD="$OWN.old"

# Let the helper finish answering the panel first.
sleep 2
cp -f "$OWN" "$OLD" 2>/dev/null || exit 1
mv -f "$NEW" "$OWN" || exit 1
systemctl --user restart "$LABEL.service"
sleep "$SETTLE"
if systemctl --user is-active --quiet "$LABEL.service"; then
  rm -f "$OLD"
  exit 0
fi
# The new helper did not stay up: the old one goes back.
mv -f "$OLD" "$OWN"
systemctl --user restart "$LABEL.service"
exit 1
