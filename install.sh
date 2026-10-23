#!/bin/sh
# MetaService installer. Run it from this folder: ./install.sh
# It opens with a welcome and a menu that stays open until you quit. Install checks the settings (.env) and the computer, builds what is
# missing and starts the parent in the background, so you can close the terminal. Every choice can also be named: ./install.sh help|readme|install|status|logs|stop|autostart|uninstall
# ./install.sh --check runs the two checks only. ./install.sh run starts the parent in this terminal. Any other --option goes to the parent with install.
cd "$(dirname "$0")" || exit 1
env_file="${METASERVICE_ENV_FILE:-control-plane/arm64/.env}"
service="scripts/parent-service.sh"
log_dir="${METASERVICE_LOG_DIR:-logs}"  # every log MetaService writes lives here; install.log is this script's own
install_log="$log_dir/install.log"

banner() {
  echo "=================================================="
  echo "  MetaService"
  echo "  made by Kurnia Massidik"
  echo "=================================================="
  echo
}

menu() {
  echo "  1  Help             what each command does"
  echo "  2  README           how to install, step by step"
  echo "  3  Install          check this computer, install what is missing, build and start in the background"
  echo "  4  Status           is it running?"
  echo "  5  Logs             the last lines of what it says"
  echo "  6  Stop             stop MetaService"
  echo "  7  Uninstall        stop it and remove everything MetaService made here (it asks first)"
  echo "  8  Quit"
  echo
}

show_help() {
  echo "  ./install.sh              the welcome and the menu (it stays open until you choose 8)"
  echo "  ./install.sh help         what you are reading"
  echo "  ./install.sh readme       how to install, step by step"
  echo "  ./install.sh install      check, build, and start in the background"
  echo "  ./install.sh status       is it running?"
  echo "  ./install.sh logs         the last lines of what it says"
  echo "  ./install.sh stop         stop MetaService"
  echo "  ./install.sh uninstall    remove the builds, packages and data (it asks first; --yes, --keep-data and --env change that)"
  echo "  ./install.sh --check      only the two checks; nothing is built or started"
  echo "  ./install.sh install --skip-container   install without Apple's container tool (no VMs on this Mac)"
  echo "  ./install.sh install --skip-nmap         install without nmap (Find machines sees fewer computers)"
  echo "  ./install.sh run          start in this terminal (stops when you close it)"
  echo "  ./install.sh remote check|plan|up|status|down   reach the panel from outside through its own Cloudflare tunnel (see the README)"
  echo "  ./install.sh autostart on|off|status   start MetaService (and the remote connector) at boot, with nobody logged in; on needs sudo"
  echo "  ./install.sh --agent-bind 192.168.100.40   any other --option goes to the parent, with install"
}

autostart="scripts/autostart.sh"

# With autostart on, launchd restarts the parent the moment it stops, so a plain stop would fight it.
stop_now() {
  if sh "$autostart" installed; then
    echo "      Autostart is on: launchd starts MetaService again as soon as it stops, so it was not stopped."
    echo "      To stop it for good, run ./install.sh autostart off (it needs sudo). Start it by hand again later with ./install.sh install."
    return 1
  fi
  sh "$service" stop
}

status_now() {
  sh "$service" status
  sh "$autostart" installed || return 0
  sh "$autostart" status
}

show_readme() {
  sed -n '/^## Install/,/^## What works today/p' README.md | sed '$d'
}

run_checks() {
  command -v python3 >/dev/null 2>&1 || { echo "Python 3 is missing, and the checks need it. Install it (macOS: xcode-select --install), then try again."; return 1; }
  echo "[1/4] Checking the settings (.env)"
  python3 scripts/check_env.py "$env_file" || return 1
  echo "      ✓ The settings are fine."
  echo "[2/4] Checking this computer"
  python3 scripts/check_computer.py || return 1
}

install_now() {
  skip_container=no
  skip_nmap=no
  count=$#
  while [ "$count" -gt 0 ]; do
    option="$1"; shift; count=$((count - 1))
    case "$option" in
      --skip-container) skip_container=yes ;;
      --skip-nmap) skip_nmap=yes ;;
      *) set -- "$@" "$option" ;;
    esac
  done
  run_checks || return 1
  if [ "$1" = "--check" ]; then
    echo "Checks done. Nothing was built or started."
    return 0
  fi
  echo "[3/4] Apple's container tool (it creates the VMs)"
  if [ "$skip_container" = yes ]; then
    sh scripts/install-container.sh --no-install || return 1
  else
    sh scripts/install-container.sh || { echo "      You can go on without VMs: ./install.sh install --skip-container"; return 1; }
  fi
  echo "      nmap (it finds computers on the network)"
  if [ "$skip_nmap" = yes ]; then sh scripts/install-nmap.sh --no-install; else sh scripts/install-nmap.sh; fi
  echo "[4/4] Building and starting MetaService in the background (the first time takes a few minutes)"
  sh "$service" start "$@" || return 1
  echo "      You can close this terminal. Stop it with ./install.sh stop"
}

# Runs install_now and appends everything it prints to logs/install.log as well. Errors stay on stderr; the exit code is install_now's, not tee's.
install_logged() {
  mkdir -p "$log_dir" && chmod 700 "$log_dir" || return 1
  (umask 077; : >> "$install_log") || return 1
  scratch="$(mktemp -d)" || return 1
  mkfifo "$scratch/errors" || return 1
  tee -a "$install_log" < "$scratch/errors" >&2 &
  errors_copy=$!
  { echo "=== install $(date '+%Y-%m-%d %H:%M:%S') ==="; install_now "$@"; echo $? > "$scratch/status"; } 2> "$scratch/errors" | tee -a "$install_log"
  wait "$errors_copy"
  status="$(cat "$scratch/status")"
  rm -rf "$scratch"
  return "${status:-1}"
}

choose() {
  while true; do
    menu
    printf "Choose 1 to 8: "
    read -r answer || { echo; exit 0; }
    echo
    case "$answer" in
      1|help) show_help ;;
      2|readme) show_readme ;;
      3|install) install_logged ;;
      4|status) status_now ;;
      5|logs) sh "$service" logs ;;
      6|stop) stop_now ;;
      7|uninstall) sh scripts/uninstall.sh ;;
      8|quit|q) echo "Bye."; exit 0 ;;
      *) echo "Please type a number from 1 to 8." ;;
    esac
    echo
  done
}

banner
case "$1" in
  help|--help|-h) show_help ;;
  readme|--readme) show_readme ;;
  install) shift; install_logged "$@"; exit $? ;;
  status) status_now; exit $? ;;
  stop) stop_now; exit $? ;;
  logs) sh "$service" logs ;;
  autostart) shift; sh "$autostart" "$@"; exit $? ;;
  uninstall) shift; sh scripts/uninstall.sh "$@"; exit $? ;;
  run) shift; run_checks || exit 1; exec scripts/start-parent.sh "$@" ;;
  remote) shift; run_checks || exit 1; exec python3 scripts/remote_access --env "$env_file" "$@" ;;
  --*) install_logged "$@"; exit $? ;;
  "")
    if [ -t 0 ]; then choose; else menu; echo "Run ./install.sh install to install, or ./install.sh help for the commands."; fi ;;
  *) echo "I do not know \"$1\"."; echo; show_help; exit 1 ;;
esac
