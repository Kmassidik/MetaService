#!/bin/sh
# Makes sure nmap is installed. The panel's "Find machines" uses it to sweep the network; without it the scan only has the ARP table and the Agent-port probe.
# Missing: it installs only nmap, with Homebrew, as you (no sudo). It never runs `brew update` or `brew upgrade`, because that can change other formulas on this Mac
# (the Mac mini's MAAS has patched Homebrew files that an update would undo). nmap is optional: whatever goes wrong, this says so and exits 0, and the install goes on.
# With --no-install a missing nmap is left missing (and said so). METASERVICE_NMAP_PATHS and METASERVICE_BREW are for the tests.
paths="${METASERVICE_NMAP_PATHS:-/opt/homebrew/bin/nmap /usr/local/bin/nmap /usr/bin/nmap /run/current-system/sw/bin/nmap}"
brew_path="${METASERVICE_BREW:-}"

# The same places the parent looks for nmap (ScanService.nmapSearch).
installed_at() { for path in $paths; do [ -x "$path" ] && { echo "$path"; return 0; }; done; return 1; }

find_brew() {
  [ -n "$brew_path" ] && { [ -x "$brew_path" ] && echo "$brew_path"; return; }
  command -v brew 2>/dev/null || { for path in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$path" ] && { echo "$path"; return; }; done; }
}

left_out() {
  echo "      ! $1"
  echo "        \"Find machines\" will see fewer computers (the ARP table and the Agent port only). You can still add a computer by its address."
  exit 0
}

if bin="$(installed_at)"; then
  echo "      ✓ nmap is installed ($bin)."
  exit 0
fi
[ "$1" = --no-install ] && left_out "nmap is not installed, and you chose to go without it (--skip-nmap)."
brew="$(find_brew)"
[ -n "$brew" ] || left_out "nmap is not installed, and Homebrew is not here to install it."
echo "      Installing nmap with Homebrew (only nmap; no update of anything else, no password) ..."
if ! HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_ENV_HINTS=1 "$brew" install nmap >/dev/null 2>&1; then
  left_out "Homebrew could not install nmap. Try yourself and read what it says: brew install nmap"
fi
bin="$(installed_at)" || left_out "Homebrew finished, but nmap is not where MetaService looks for it."
echo "      ✓ nmap is installed ($bin)."
