#!/bin/sh
# MetaService installer. Run it from this folder: ./install.sh
# It opens with a welcome and a menu that stays open until you quit. Install checks the settings (.env) and the computer, builds what is
# missing and starts the parent in the background, so you can close the terminal. Every choice can also be named: ./install.sh help|readme|install|status|logs|stop|login on|login off
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
  echo "  3  Install          check this computer, then build and start in the background"
  echo "  4  Status           is it running?"
  echo "  5  Logs             the last lines of what it says"
  echo "  6  Stop             stop MetaService"
  echo "  7  Start at login   currently $(sh "$service" login state); choose it again to switch"
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
  echo "  ./install.sh login on     start MetaService when you log in, and again if it stops"
  echo "  ./install.sh login off    do not start it at login any more"
  echo "  ./install.sh --check      only the two checks; nothing is built or started"
  echo "  ./install.sh run          start in this terminal (stops when you close it)"
  echo "  ./install.sh --agent-bind 192.168.100.40   any other --option goes to the parent, with install"
}

show_readme() {
  sed -n '/^## Install/,/^## What works today/p' README.md | sed '$d'
}

run_checks() {
  command -v python3 >/dev/null 2>&1 || { echo "Python 3 is missing, and the checks need it. Install it (macOS: xcode-select --install), then try again."; return 1; }
  echo "[1/3] Checking the settings (.env)"
  python3 scripts/check_env.py "$env_file" || return 1
  echo "      ✓ The settings are fine."
  echo "[2/3] Checking this computer"
  python3 scripts/check_computer.py || return 1
}

install_now() {
  run_checks || return 1
  if [ "$1" = "--check" ]; then
    echo "Checks done. Nothing was built or started."
    return 0
  fi
  echo "[3/3] Building and starting MetaService in the background (the first time takes a few minutes)"
  sh "$service" start "$@" || return 1
  echo "      You can close this terminal. Stop it with ./install.sh stop"
}

toggle_login() {
  if [ "$(sh "$service" login state)" = on ]; then sh "$service" login off; else sh "$service" login on; fi
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
      7|login) toggle_login ;;
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
  login) sh "$service" login "$2"; exit $? ;;
  run) shift; run_checks || exit 1; exec scripts/start-parent.sh "$@" ;;
  --*) install_now "$@"; exit $? ;;
  "")
    if [ -t 0 ]; then choose; else menu; echo "Run ./install.sh install to install, or ./install.sh help for the commands."; fi ;;
  *) echo "I do not know \"$1\"."; echo; show_help; exit 1 ;;
esac
