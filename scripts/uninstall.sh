#!/bin/sh
# Removes what MetaService made on this computer: the running parent, the login item, the builds, the packages and (unless told otherwise) the data.
# It never removes the source code, git, Apple's container tool or anything outside this folder. It asks first.
# Usage: uninstall.sh [--yes] [--keep-data] [--env]    --yes: do not ask    --keep-data: keep control-plane/arm64/state    --env: also remove the .env settings file
# Without --yes it needs a keyboard to answer on. METASERVICE_ROOT points it at another folder (the tests use that).
here="$(cd "$(dirname "$0")/.." && pwd)"
root="${METASERVICE_ROOT:-$here}"
service="$here/scripts/parent-service.sh"
yes=no; keep_data=no; remove_env=no
for option in "$@"; do
  case "$option" in
    --yes) yes=yes ;;
    --keep-data) keep_data=yes ;;
    --env) remove_env=yes ;;
    *) echo "I do not know $option. Usage: uninstall.sh [--yes] [--keep-data] [--env]"; exit 2 ;;
  esac
done

# Only a MetaService folder, never the home folder or the top of the disk.
{ [ -f "$root/install.sh" ] && [ -d "$root/control-plane" ] && [ "$root" != "/" ] && [ "$root" != "$HOME" ]; } || { echo "$root is not a MetaService folder. Nothing was removed."; exit 1; }

builds="control-plane/arm64/.build agent/macos/.build agent/linux/target shared/metaservice-shared/.build"
packages="frontend/node_modules bundles/chat/ui/node_modules"
runtime="control-plane/arm64/run"
data="control-plane/arm64/state"
caches="$(cd "$root" && find . -name __pycache__ -type d -not -path '*/node_modules/*' -not -path './.git/*' -prune | sed 's#^\./##')"

present() { for path in "$@"; do [ -e "$root/$path" ] && echo "$path"; done; }
kilobytes() { for path in "$@"; do du -sk "$root/$path" 2>/dev/null; done | awk '{sum += $1} END {print sum + 0}'; }
human() { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f GB", k/1048576; else if (k >= 1024) printf "%.0f MB", k/1024; else printf "%d KB", k }'; }

found_builds="$(present $builds)"; found_packages="$(present $packages)"; found_runtime="$(present $runtime)"; found_data="$(present $data)"
[ "$keep_data" = yes ] && found_data=""
remove_list="$found_builds $found_packages $found_runtime $found_data $caches"
if [ -z "$(echo $remove_list)" ] && { [ "$remove_env" = no ] || [ ! -e "$root/control-plane/arm64/.env" ]; }; then
  echo "Nothing to remove: no builds, packages or data are here."
  exit 0
fi

row() { printf "  %9s  %-12s %s\n" "$(human "$(kilobytes $3)")" "$1" "$2"; }
echo "This removes what MetaService made on this computer:"
[ -n "$found_builds" ] && row "builds" "$(echo $found_builds)" "$found_builds"
[ -n "$found_packages" ] && row "packages" "$(echo $found_packages)" "$found_packages"
[ -n "$found_runtime" ] && row "run files" "$found_runtime (the background pid and log)" "$found_runtime"
[ -n "$found_data" ] && row "your data" "$found_data (the machines, the admin login and the keys)" "$found_data"
[ -n "$caches" ] && row "Python caches" "" "$caches"
[ "$keep_data" = yes ] && echo "  (your data stays: --keep-data)"
echo "It also stops MetaService and turns off its login item."
echo "It keeps: the source code and git, Apple's container tool, and $([ "$remove_env" = yes ] && echo "nothing else of yours" || echo "your .env settings")."
echo

if [ "$yes" = no ]; then
  [ -t 0 ] || { echo "No keyboard to ask on. Run it in a terminal, or add --yes. Nothing was removed."; exit 1; }
  printf "Type yes to remove them: "
  read -r answer || answer=""
  [ "$answer" = yes ] || { echo "Nothing was removed."; exit 0; }
  if [ "$remove_env" = no ] && [ -e "$root/control-plane/arm64/.env" ]; then
    printf "Also remove your .env settings file? [y/N] "
    read -r answer || answer=""
    case "$answer" in y|Y|yes) remove_env=yes ;; esac
  fi
fi

echo "Stopping MetaService..."
sh "$service" login off >/dev/null
sh "$service" stop >/dev/null
for path in $remove_list; do rm -rf "${root:?}/$path"; done
[ "$remove_env" = yes ] && rm -f "$root/control-plane/arm64/.env"
echo "Removed."
echo "The source code is still in $root. To remove MetaService completely, delete that folder."
