#!/bin/sh
# MetaService installer. Run it from this folder: ./install.sh
# It opens with a welcome and a menu that stays open until you quit. Install checks the settings (.env) and the computer, builds what is
# missing and starts the parent in the background, so you can close the terminal. Every choice can also be named: ./install.sh help|readme|install|status|logs|stop|uninstall
# ./install.sh --check runs the two checks only. ./install.sh run starts the parent in this terminal. Any other --option goes to the parent with install.
cd "$(dirname "$0")" || exit 1
env_file="${METASERVICE_ENV_FILE:-control-plane/arm64/.env}"
service="scripts/parent-service.sh"

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
  echo "  ./install.sh run          start in this terminal (stops when you close it)"
  echo "  ./install.sh --agent-bind 192.168.100.40   any other --option goes to the parent, with install"
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
  count=$#
  while [ "$count" -gt 0 ]; do
    option="$1"; shift; count=$((count - 1))
    if [ "$option" = --skip-container ]; then skip_container=yes; else set -- "$@" "$option"; fi
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
  echo "[4/4] Building and starting MetaService in the background (the first time takes a few minutes)"
  sh "$service" start "$@" || return 1
  echo "      You can close this terminal. Stop it with ./install.sh stop"
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
      3|install) install_now ;;
      4|status) sh "$service" status ;;
      5|logs) sh "$service" logs ;;
      6|stop) sh "$service" stop ;;
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
  install) shift; install_now "$@"; exit $? ;;
  status|logs|stop) sh "$service" "$1" ;;
  uninstall) shift; sh scripts/uninstall.sh "$@"; exit $? ;;
  run) shift; run_checks || exit 1; exec scripts/start-parent.sh "$@" ;;
  --*) install_now "$@"; exit $? ;;
  "")
    if [ -t 0 ]; then choose; else menu; echo "Run ./install.sh install to install, or ./install.sh help for the commands."; fi ;;
  *) echo "I do not know \"$1\"."; echo; show_help; exit 1 ;;
esac
