#!/bin/sh
# Makes the Mac Mini ready to build and run the join-share hub: Homebrew, the WireGuard tools, and the Rust toolchain.
# Safe to run again: it installs only what is missing and prints a found / missing list. Nothing of MAAS or MetaService is touched.
set -eu

BREW=/opt/homebrew/bin/brew
CARGO="$HOME/.cargo/bin/cargo"

say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

say "== before"
for tool in "$BREW" "$CARGO" wg wg-quick wireguard-go; do
  if [ -x "$tool" ] || have "$tool"; then say "found    $tool"; else say "missing  $tool"; fi
done

if [ ! -x "$BREW" ]; then
  say "== installing Homebrew (official installer, no prompts)"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

eval "$("$BREW" shellenv)"
for formula in wireguard-tools wireguard-go; do
  if "$BREW" list --formula "$formula" >/dev/null 2>&1; then continue; fi
  say "== brew install $formula"
  "$BREW" install "$formula"
done

if [ ! -x "$CARGO" ]; then
  say "== installing the Rust toolchain (rustup, minimal profile, under $HOME/.cargo)"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
fi

say "== after"
"$BREW" --prefix >/dev/null
for tool in "$BREW" "$CARGO" /opt/homebrew/bin/wg /opt/homebrew/bin/wg-quick /opt/homebrew/bin/wireguard-go; do
  if [ -x "$tool" ]; then say "found    $tool"; else say "MISSING  $tool"; exit 1; fi
done
"$CARGO" --version
"$HOME/.cargo/bin/rustc" --version
