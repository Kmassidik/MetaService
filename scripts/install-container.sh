#!/bin/sh
# Makes sure Apple's container tool (what creates VMs on a Mac) is installed and its service is running.
# Missing: it downloads Apple's signed installer package, checks the checksum and Apple's signature, installs it (the Mac asks for the password once) and starts the service.
# With --no-install a missing tool is left missing (and said so); a tool that is there is still checked and its service started.
# Exit 0 when the tool is ready (or left out on request), 1 when it could not be made ready. The METASERVICE_CONTAINER_* variables are for the tests.
version="1.5.0"
# The checksum of Apple's container-1.5.0-installer-signed.pkg. A new version needs its checksum put here after it has been looked at.
expected_sha256="${METASERVICE_CONTAINER_SHA256:-a24808cb202318fa1c3bbee0c6c6887fe1225fe899d7b687a0ddd939bd6573f8}"
url="${METASERVICE_CONTAINER_URL:-https://github.com/apple/container/releases/download/$version/container-$version-installer-signed.pkg}"
paths="${METASERVICE_CONTAINER_PATHS:-/usr/local/bin/container /opt/homebrew/bin/container /usr/bin/container}"

installed_at() { for path in $paths; do [ -x "$path" ] && { echo "$path"; return 0; }; done; return 1; }

stop_with() {
  echo "      ✗ $1"
  echo "        $2"
  exit 1
}

download() {
  echo "      Downloading Apple's container tool $version (about 118 MB) from github.com/apple/container ..."
  curl -fL --retry 2 --progress-bar -o "$1" "$url" || stop_with "The download failed." "Check the internet connection and try again, or install it yourself from github.com/apple/container."
}

verify() {
  actual="$(shasum -a 256 "$1" | cut -d' ' -f1)"
  [ "$actual" = "$expected_sha256" ] || stop_with "The download is not the file we expected (its checksum is different). Nothing was installed." "Try again. If it happens again, install it yourself from github.com/apple/container."
  signature="$(pkgutil --check-signature "$1" 2>&1)"
  echo "$signature" | grep -q "Developer ID Installer: Apple Inc." && echo "$signature" | grep -q "trusted by the Apple notary service" ||
    stop_with "The package is not signed and notarized by Apple. Nothing was installed." "Install it yourself from github.com/apple/container if you trust the source."
  echo "      ✓ The file is the one we expect, and Apple signed it."
}

install_package() {
  echo "      Installing it. Your Mac asks for your password once, here in this terminal."
  sudo installer -pkg "$1" -target / >/dev/null || stop_with "The install did not finish (a wrong or cancelled password stops it)." "Run ./install.sh again to try once more."
  bin="$(installed_at)" || stop_with "The installer ran but the tool is not where MetaService looks for it." "Look in /usr/local/bin for container."
}

ensure_running() {
  "$1" system status >/dev/null 2>&1 && { echo "      ✓ Apple's container service is running."; return 0; }
  echo "      Starting Apple's container service (the first time it also downloads a small Linux kernel) ..."
  "$1" system start --enable-kernel-install >/dev/null 2>&1 && "$1" system status >/dev/null 2>&1 ||
    stop_with "Apple's container service did not start." "Run this yourself and read what it says: container system start"
  echo "      ✓ Apple's container service is running."
}

if bin="$(installed_at)"; then
  echo "      ✓ Apple's container tool is installed ($bin)."
elif [ "$1" = --no-install ]; then
  echo "      Skipped. This Mac cannot create VMs until the tool is installed."
  exit 0
else
  [ -t 0 ] || stop_with "The tool is missing, and installing it needs a terminal to ask for your password." "Run ./install.sh in a terminal, or add --skip-container to go without VMs."
  work="$(mktemp -d)" && trap 'rm -rf "$work"' EXIT
  download "$work/container.pkg"
  verify "$work/container.pkg"
  install_package "$work/container.pkg"
  echo "      ✓ Apple's container tool is installed ($bin)."
fi
ensure_running "$bin"
