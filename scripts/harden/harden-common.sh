# shellcheck shell=bash
# shellcheck disable=SC2034  # variables here are read by the scripts that source this file
# Shared helpers for harden-linux.sh and harden-mac.sh. Sourced, never run by itself.
#
# Safety design (the same on both machine classes):
#   1. `check` only reads. `apply` changes things, and only after the guards pass.
#   2. Every file the script touches is copied to a backup folder first, and a manifest
#      says how to put everything back. `rollback` follows the manifest.
#   3. After `apply`, an automatic rollback is scheduled. Nothing is final until you run `confirm`.
#   4. If `apply` fails half way, it rolls itself back before exiting.
#
# Test hooks (never needed on a real machine):
#   HARDEN_ROOT=<folder>      every system path (/etc, /var/...) is prefixed with this folder.
#   HARDEN_DRY_COMMANDS=1     systemctl, apt-get, sshd, nft ... are not run, only written to a call log.
# The two must be used together: a prefix without recorders, or recorders without a prefix, is refused.

HARDEN_ROOT="${HARDEN_ROOT:-}"
HARDEN_DRY_COMMANDS="${HARDEN_DRY_COMMANDS:-0}"
HARDEN_FAKE_FAIL="${HARDEN_FAKE_FAIL:-}"        # dry mode: command names that should "fail"
HARDEN_FAKE_OUT_DIR="${HARDEN_FAKE_OUT_DIR:-}"  # dry mode: folder with canned command output
HARDEN_FAKE_MISSING="${HARDEN_FAKE_MISSING:-}"  # dry mode: command names that are "not installed"

EXIT_REFUSED=3          # a guard said no; nothing was changed
# shellcheck disable=SC2034  # used by harden-mac.sh
REVERT_SECONDS=300      # how long the owner has to run `confirm` before the automatic rollback
MIN_BLOCK_PREFIX=8      # a blocklist range wider than a /8 is almost certainly a typo
LAN_RANGE="192.168.0.0/24"
PROTECTED_RANGES="127.0.0.0/8 $LAN_RANGE"       # never blockable
USERNAME_PATTERN='^[a-z_][a-z0-9_-]{0,31}$'
SAFE_WORDS_PATTERN='^[A-Za-z0-9_./:@= -]+$'     # what a manifest command may contain
SSH_KEY_PATTERN='(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]]+AAAA[A-Za-z0-9+/=]+'
TAB="$(printf '\t')"

CHANGES_MADE=0
APPLY_FINISHED=0
# shellcheck disable=SC2034  # read by the scripts that source this file
FILE_CHANGED=0
RUN_DIR=""

# ---------------------------------------------------------------- messages and log

say() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

# Writes one line to the log file, if the log folder exists and we may write to it.
log_line() {
  [ -n "${LOG_FILE:-}" ] || return 0
  [ -w "$(dirname "$LOG_FILE")" ] || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE"
}

# A guard said no. Nothing has been changed (or, during apply, the exit trap undoes it).
refuse() {
  printf 'REFUSED: %s\n' "$*" >&2
  log_line "REFUSED: $*"
  exit "$EXIT_REFUSED"
}

note() { say "$*"; log_line "$*"; }

# ---------------------------------------------------------------- paths and commands

# Prefixes a system path with HARDEN_ROOT (empty on a real machine).
host_path() { printf '%s%s' "$HARDEN_ROOT" "$1"; }

is_dry() { [ "$HARDEN_DRY_COMMANDS" = 1 ]; }

setup_environment() {
  if [ -n "$HARDEN_ROOT" ] && ! is_dry; then
    refuse "HARDEN_ROOT is only for tests and needs HARDEN_DRY_COMMANDS=1, otherwise real commands would run."
  fi
  if is_dry && [ -z "$HARDEN_ROOT" ]; then
    refuse "HARDEN_DRY_COMMANDS=1 needs HARDEN_ROOT, otherwise real files would be written."
  fi
  CALL_LOG="${HARDEN_CALL_LOG:-$(host_path /harden-calls.log)}"
  LOG_FILE="$(host_path /var/log/metaservice-harden.log)"
}

# Runs a system command, or records it in dry mode. All commands go through here.
sys() {
  if ! is_dry; then
    command "$@"
    return
  fi
  printf '%s\n' "$*" >>"$CALL_LOG"
  case " $HARDEN_FAKE_FAIL " in *" $1 "*) return 1 ;; esac
  return 0
}

# Like sys, but prints the command's output. In dry mode the output comes from a canned file.
sys_out() {
  if ! is_dry; then
    command "$@"
    return
  fi
  printf '%s\n' "$*" >>"$CALL_LOG"
  case " $HARDEN_FAKE_FAIL " in *" $1 "*) return 1 ;; esac
  local key canned
  key="$(printf '%s' "$*" | tr -cs 'A-Za-z0-9' '_' | sed 's/_$//')"
  canned="$HARDEN_FAKE_OUT_DIR/$key"
  if [ -n "$HARDEN_FAKE_OUT_DIR" ] && [ -f "$canned" ]; then
    cat "$canned"
  fi
  return 0
}

have_command() {
  if is_dry; then
    case " $HARDEN_FAKE_MISSING " in *" $1 "*) return 1 ;; esac
    return 0
  fi
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  is_dry && return 0
  [ "$(id -u)" = 0 ] || refuse "apply, confirm and rollback change the system. Run it with sudo."
}

# ---------------------------------------------------------------- input validation

# The person who ran sudo. Their key login must keep working.
invoking_user() {
  local user="${SUDO_USER:-}"
  [ -n "$user" ] || refuse "Run this with sudo from your own account (SUDO_USER is empty), so I know whose SSH key login to protect."
  [ "$user" != root ] || refuse "Do not run this from a root login. Use your normal account with sudo, so I know whose key login to protect."
  valid_username "$user" || refuse "The user name '$user' has unusual characters."
  printf '%s' "$user"
}

valid_username() { printf '%s' "$1" | grep -Eq "$USERNAME_PATTERN"; }

# Turns "bob, carol" into a checked, space separated list. Anything odd stops the script.
validated_user_list() {
  local raw word out=""
  raw="$(printf '%s' "$1" | tr ',' ' ')"
  for word in $raw; do
    valid_username "$word" || refuse "'$word' is not a valid user name (lower case letters, digits, _ and - only)."
    out="$out $word"
  done
  printf '%s' "${out# }"
}

# Dotted address to a number. The input must already match the strict octet pattern.
ip_to_number() {
  local a b c d
  # shellcheck disable=SC2046  # splitting on spaces is the point
  set -- $(printf '%s' "$1" | tr . ' ')
  a="$1"; b="$2"; c="$3"; d="$4"
  printf '%s' $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

prefix_mask() { printf '%s' $(( (0xFFFFFFFF << (32 - $1)) & 0xFFFFFFFF )); }

# Strict check: a.b.c.d/n, no leading zeros, octets 0-255, prefix MIN_BLOCK_PREFIX-32, aligned to the prefix.
# The pattern runs first, so nothing but digits and dots ever reaches the arithmetic.
is_valid_cidr() {
  local cidr="$1" address prefix octet number
  local digits='(0|[1-9][0-9]{0,2})'
  printf '%s' "$cidr" | grep -Eq "^${digits}(\\.${digits}){3}/(0|[1-9][0-9]?)\$" || return 1
  address="${cidr%/*}"
  prefix="${cidr#*/}"
  [ "$prefix" -ge "$MIN_BLOCK_PREFIX" ] && [ "$prefix" -le 32 ] || return 1
  for octet in $(printf '%s' "$address" | tr . ' '); do
    [ "$octet" -le 255 ] || return 1
  done
  number="$(ip_to_number "$address")"
  [ $(( number & $(prefix_mask "$prefix") )) -eq "$number" ]
}

# Prints "first last" as numbers for a valid range.
cidr_bounds() {
  local start
  start="$(ip_to_number "${1%/*}")"
  printf '%s %s' "$start" $(( start | (~$(prefix_mask "${1#*/}") & 0xFFFFFFFF) ))
}

cidrs_overlap() {
  local a_start a_end b_start b_end
  read -r a_start a_end <<<"$(cidr_bounds "$1")"
  read -r b_start b_end <<<"$(cidr_bounds "$2")"
  [ "$a_start" -le "$b_end" ] && [ "$b_start" -le "$a_end" ]
}

# Checks a whole blocklist (space separated). One bad entry refuses everything.
validate_blocklist() {
  local cidr protected
  for cidr in $1; do
    is_valid_cidr "$cidr" || refuse "Blocklist entry '$cidr' is not a clean range like 203.0.113.0/24 (prefix $MIN_BLOCK_PREFIX to 32, no leading zeros, aligned)."
    for protected in $PROTECTED_RANGES; do
      if cidrs_overlap "$cidr" "$protected"; then
        refuse "Blocklist entry '$cidr' overlaps $protected (your LAN or this machine). Refusing so you cannot lock yourself out."
      fi
    done
  done
  return 0
}

# ---------------------------------------------------------------- the key guard

user_home() {
  if is_dry && [ -n "${HARDEN_USER_HOME:-}" ]; then
    printf '%s' "$HARDEN_USER_HOME"
    return
  fi
  lookup_home "$1"
}

# ls -ld fields: mode, owner. Used because stat has different flags on Linux and macOS.
# shellcheck disable=SC2012  # only mode and owner are read, paths are ours
mode_and_owner() { ls -ld "$1" | awk '{print $1, $3}'; }

# True when the group or others can write to the path (sshd's StrictModes would then ignore the key).
writable_by_others() {
  local mode
  mode="$(mode_and_owner "$1" | cut -d' ' -f1)"
  [ "$(printf '%s' "$mode" | cut -c6)" = w ] || [ "$(printf '%s' "$mode" | cut -c9)" = w ]
}

# Refuses to go on unless key login is certain to keep working for this user.
require_key_login_safe() {
  local user="$1" home keys path owner expected_owner
  home="$(user_home "$user")"
  [ -n "$home" ] || refuse "Cannot find the home folder of '$user'."
  keys="$home/.ssh/authorized_keys"
  [ -f "$keys" ] || refuse "$keys does not exist. Turning off passwords would lock '$user' out. Add your public key first."
  grep -v '^[[:space:]]*#' "$keys" | grep -Eq "$SSH_KEY_PATTERN" \
    || refuse "$keys has no usable public key. Turning off passwords would lock '$user' out."
  expected_owner="$user"
  is_dry && expected_owner="$(id -un)"
  for path in "$home" "$home/.ssh" "$keys"; do
    owner="$(mode_and_owner "$path" | cut -d' ' -f2)"
    [ "$owner" = "$expected_owner" ] || refuse "$path is owned by '$owner', not '$user'. sshd would ignore the key."
    if writable_by_others "$path"; then
      refuse "$path can be written by others. sshd would ignore the key (StrictModes). Fix with: chmod go-w $path"
    fi
  done
  [ "${KEY_LOGIN_TESTED:-0}" = 1 ] || refuse "Second check missing. Keep this SSH session open, open a NEW terminal, log in with your key only (ssh -o PasswordAuthentication=no ...), and when that works run apply again with --confirm-key-login."
  return 0
}

# ---------------------------------------------------------------- backups and manifest

# Creates the backup folder for this apply run, once, and points `rollback` at it.
ensure_run_dir() {
  [ -z "$RUN_DIR" ] || return 0
  RUN_DIR="$STATE_DIR/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$RUN_DIR/files"
  chmod 700 "$STATE_DIR" "$RUN_DIR"
  : >"$RUN_DIR/manifest"
  printf '%s\n' "$RUN_DIR" >"$STATE_DIR/last-apply"
  note "Backup folder for this run: $RUN_DIR"
}

manifest_has() {
  awk -F'\t' -v target="$1" '$2 == target { found = 1 } END { exit !found }' "$RUN_DIR/manifest"
}

manifest_add() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$RUN_DIR/manifest"; }

# Copies a file that is about to change into the backup folder (or notes that it did not exist).
backup_target() {
  local target="$1" copy
  ensure_run_dir
  if manifest_has "$target"; then
    return 0
  fi
  if [ ! -e "$target" ]; then
    manifest_add remove "$target"
    return 0
  fi
  copy="$RUN_DIR/files/$(printf '%s' "$target" | tr '/' '_')"
  cp -p "$target" "$copy"
  manifest_add restore "$target" "$copy"
}

# A command to run during rollback BEFORE files are restored, e.g. stop a service we started.
record_undo() { ensure_run_dir; manifest_add undo "$1"; }

# A command to run during rollback AFTER files are restored, e.g. reload ssh.
record_after() { ensure_run_dir; manifest_add after "$1"; }

# Writes text to a file atomically with a given mode.
write_atomic() {
  local target="$1" mode="$2" content="$3" temp
  mkdir -p "$(dirname "$target")"
  temp="$target.metaservice-tmp"
  printf '%s\n' "$content" >"$temp"
  chmod "$mode" "$temp"
  mv "$temp" "$target"
}

# Installs a managed file. Does nothing if it is already exactly right.
# Sets FILE_CHANGED=1 when it wrote something.
install_managed_file() {
  local target="$1" mode="$2" content="$3"
  FILE_CHANGED=0
  if [ -f "$target" ] && [ "$(cat "$target")" = "$content" ]; then
    note "  already in place: $target"
    return 0
  fi
  backup_target "$target"
  write_atomic "$target" "$mode" "$content"
  FILE_CHANGED=1
  CHANGES_MADE=1
  note "  wrote $target"
}

# Runs a manifest command if it only contains safe characters. Failures are reported, not fatal.
run_manifest_words() {
  local words="$1"
  if ! printf '%s' "$words" | grep -Eq "$SAFE_WORDS_PATTERN"; then
    warn "skipping unsafe manifest command"
    return 0
  fi
  set -f
  # shellcheck disable=SC2086  # the words were written by this script and checked above
  sys $words || warn "rollback step failed (continuing): $words"
  set +f
}

# ---------------------------------------------------------------- rollback and confirm

restore_file() {
  local target="$1" copy="$2"
  cp -p "$copy" "$target.metaservice-tmp"
  mv "$target.metaservice-tmp" "$target"
  note "  restored $target"
}

run_manifest_pass() {
  local wanted="$1" manifest="$2" kind first second
  while IFS="$TAB" read -r kind first second; do
    [ "$kind" = "$wanted" ] || continue
    case "$wanted" in
      undo | after) run_manifest_words "$first" ;;
      restore) restore_file "$first" "$second" ;;
      remove) rm -f "$first"; note "  removed $first (it did not exist before)" ;;
    esac
  done <"$manifest"
}

run_rollback() {
  local pointer="$STATE_DIR/last-apply" dir
  if [ ! -f "$pointer" ]; then
    note "Nothing to roll back: no apply has been recorded."
    return 0
  fi
  dir="$(cat "$pointer")"
  [ -f "$dir/manifest" ] || refuse "The manifest $dir/manifest is missing."
  note "Rolling back the changes recorded in $dir"
  run_manifest_pass undo "$dir/manifest"
  run_manifest_pass restore "$dir/manifest"
  run_manifest_pass remove "$dir/manifest"
  run_manifest_pass after "$dir/manifest"
  mv "$pointer" "$STATE_DIR/last-rollback"
  cancel_revert
  note "Rollback finished. Check that your login still works."
}

run_confirm() {
  if [ ! -f "$STATE_DIR/last-apply" ]; then
    note "Nothing to confirm: no apply is waiting."
    return 0
  fi
  cancel_revert
  note "Confirmed. The automatic rollback is cancelled and the changes stay. (rollback still works later.)"
}

# If apply dies after changing something, undo it right away instead of leaving a half state.
apply_exit_trap() {
  local status="$1"
  trap - EXIT
  [ "$status" -ne 0 ] || return 0
  [ "$APPLY_FINISHED" = 0 ] || return 0
  [ "$CHANGES_MADE" = 1 ] || return 0
  warn "apply stopped part-way (exit $status). Undoing what it changed."
  run_rollback || true
}

# ---------------------------------------------------------------- check table

print_row() { printf '%-26s %-34s %s\n' "$1" "$2" "$3"; }

print_header() {
  print_row "CONTROL" "STATE NOW" "WHAT apply WOULD DO"
  print_row "-------" "---------" "-------------------"
}

# Prints the first uncommented value of an sshd option, following sshd's first-value-wins rule.
# Arguments: option name, then the config files in the order sshd reads them.
first_sshd_value() {
  local option="$1" file value
  shift
  for file in "$@"; do
    [ -e "$file" ] || continue
    if [ ! -r "$file" ]; then
      printf 'unreadable without sudo (%s)' "$(basename "$file")"
      return 0
    fi
    value="$(awk -v opt="$option" 'BEGIN { o = tolower(opt) } $1 !~ /^#/ && tolower($1) == o { print $2; exit }' "$file")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
  printf 'not set (default)'
}
