#!/bin/sh
# Builds the two Linux helper programs (x86_64 and ARM) with nix and puts them in the parent's builds folder.
#
#   scripts/build-linux-helpers.sh [folder]
#
# The folder defaults to control-plane/arm64/state/agent-builds. The files are named
# metaservice-agent-linux-x86_64 and metaservice-agent-linux-arm64, which is what the parent looks for.
# A SHA256SUMS file is written next to them. Nothing is copied to any other computer.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$ROOT/control-plane/arm64/state/agent-builds}"
# The systems to build, and the words that `file` must print for each one.
SYSTEMS="linux-x86_64 linux-arm64"
# The helper is the only program in the build result's bin folder.
PROGRAM_IN_RESULT="bin/metaservice-agent"
EXECUTABLE_MODE=755
# How many characters of a checksum are shown in the summary.
SHORT_SUM_LENGTH=16

# Prints what `file` must say for a system.
expected_description() {
  case "$1" in
    linux-x86_64) echo "ELF 64-bit LSB.*x86-64" ;;
    linux-arm64) echo "ELF 64-bit LSB.*ARM aarch64" ;;
    *) echo "unknown system $1" >&2; return 1 ;;
  esac
}

# Stops with a message if the file is not a Linux program for the given system.
check_kind() {
  system="$1"; path="$2"
  description="$(file -L "$path")"
  if echo "$description" | grep -Eq "$(expected_description "$system")"; then
    return 0
  fi
  echo "Refusing $system: file says: $description" >&2
  exit 1
}

# Prints the sha256 of a file, whichever tool this computer has.
checksum_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
    return 0
  fi
  shasum -a 256 "$1" | cut -d ' ' -f 1
}

# Builds one system with nix and copies the result into the target folder.
build_one() {
  system="$1"
  link="$WORK/$system"
  echo "Building $system (the first build downloads a toolchain and can take a while)..."
  (cd "$ROOT" && nix build ".#metaservice-agent-$system" -o "$link")
  built="$link/$PROGRAM_IN_RESULT"
  check_kind "$system" "$built"
  name="metaservice-agent-$system"
  cp "$built" "$TARGET/$name"
  chmod "$EXECUTABLE_MODE" "$TARGET/$name"
}

# Writes SHA256SUMS for the files in the target folder and prints one summary line per file.
summarize() {
  : > "$TARGET/SHA256SUMS"
  for system in $SYSTEMS; do
    name="metaservice-agent-$system"
    sum="$(checksum_of "$TARGET/$name")"
    echo "$sum  $name" >> "$TARGET/SHA256SUMS"
    size="$(wc -c < "$TARGET/$name" | tr -d ' ')"
    echo "$name  $size bytes  sha256 $(echo "$sum" | cut -c 1-"$SHORT_SUM_LENGTH")"
  done
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$TARGET"
for system in $SYSTEMS; do
  build_one "$system"
done
summarize
echo "Done. The files are in $TARGET. Check the sums before shipping them."
