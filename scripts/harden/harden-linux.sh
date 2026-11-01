#!/usr/bin/env bash
# Hardens an Ubuntu or Debian machine that MetaService manages (DGX Spark, RTX 5090 PC).
# You run it yourself with sudo. Nothing here reboots, restarts Docker or Incus, flushes a firewall,
# enables ufw, or touches the MetaService helper.
#
#   harden-linux.sh [check]                    read-only table: what is set now, what apply would change
#   sudo harden-linux.sh apply --confirm-key-login [--extra-users "bob,carol"]
#   sudo harden-linux.sh confirm               keep the changes (cancels the automatic rollback)
#   sudo harden-linux.sh rollback              put back the files saved by the last apply
#   sudo harden-linux.sh --updates --yes       separate step: apt update and full-upgrade (never reboots)
#
# Settings you may change are right below.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harden-common.sh
. "$SCRIPT_DIR/harden-common.sh"

# ---- settings (override with environment variables) ----------------------------------------
# Source ranges that are dropped before they reach any service. Edit here or pass BLOCKLIST_RANGES.
BLOCKLIST_RANGES="${BLOCKLIST_RANGES:-102.220.160.0/24 102.220.163.0/24 77.239.124.0/24}"
# Users besides the one who runs sudo that may log in over SSH (comma or space separated).
EXTRA_ALLOWED_USERS="${EXTRA_ALLOWED_USERS:-}"
# Only printed in the verification commands. Not used to change anything.
PUBLIC_ADDRESS="${PUBLIC_ADDRESS:-<public-address>}"
PUBLIC_PORT="${PUBLIC_PORT:-<public-port>}"

SSH_DROPIN_NAME="00-metaservice-hardening.conf"   # "00" so sshd reads it FIRST (sshd keeps the first value)
FAIL2BAN_MAX_RETRY=4
FAIL2BAN_FIND_TIME="10m"
FAIL2BAN_BAN_TIME="1h"
SSH_MAX_AUTH_TRIES=3
SSH_LOGIN_GRACE_SECONDS=20
SSH_MAX_STARTUPS="10:30:60"
BLOCKLIST_TABLE="metaservice-blocklist"
NFT_BIN="/usr/sbin/nft"
AUTO_REVERT_TIMER="5min"                          # matches REVERT_SECONDS in harden-common.sh
REVERT_UNIT="metaservice-harden-revert"
NVIDIA_PACKAGE_PATTERNS="nvidia- libnvidia- cuda-"  # never auto-upgraded: a driver change needs a planned reboot

STATE_DIR="$(host_path /var/backups/metaservice-harden)"
SSH_DIR="$(host_path /etc/ssh)"
SSH_DROPIN="$SSH_DIR/sshd_config.d/$SSH_DROPIN_NAME"
JAIL_FILE="$(host_path /etc/fail2ban/jail.d/metaservice-sshd.local)"
NFT_FILE="$(host_path /etc/metaservice-blocklist.nft)"
BLOCKLIST_UNIT_FILE="$(host_path /etc/systemd/system/metaservice-blocklist.service)"
AUTO_UPGRADES_FILE="$(host_path /etc/apt/apt.conf.d/20auto-upgrades)"
UNATTENDED_FILE="$(host_path /etc/apt/apt.conf.d/52metaservice-unattended)"
PENDING_MARKER="$STATE_DIR/revert-pending"

# ---- machine detection -----------------------------------------------------------------------

lookup_home() { getent passwd "$1" | cut -d: -f6; }

os_release_value() {
  sed -n "s/^$1=//p" "$(host_path /etc/os-release)" 2>/dev/null | tr -d '"' | head -n 1
}

# Refuses on anything that is not Ubuntu or Debian (or derived from them).
detect_machine() {
  local id id_like arch
  id="$(os_release_value ID)"
  id_like="$(os_release_value ID_LIKE)"
  arch="${HARDEN_FAKE_ARCH:-$(uname -m)}"
  case " $id $id_like " in
    *" ubuntu "* | *" debian "*) ;;
    *) refuse "This script is for Ubuntu or Debian. This machine says: '${id:-unknown}'. Nothing was changed." ;;
  esac
  note "Machine: $id ($arch). Supported."
}

# ---- desired file contents -------------------------------------------------------------------

ssh_dropin_content() {
  cat <<EOF
# Managed by MetaService harden-linux.sh. Remove with: sudo harden-linux.sh rollback
# Named 00-* because sshd keeps the FIRST value it reads, so later files (cloud-init) cannot undo this.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $1
MaxAuthTries $SSH_MAX_AUTH_TRIES
LoginGraceTime $SSH_LOGIN_GRACE_SECONDS
MaxStartups $SSH_MAX_STARTUPS
EOF
}

jail_content() {
  cat <<EOF
# Managed by MetaService harden-linux.sh
[sshd]
enabled = true
maxretry = $FAIL2BAN_MAX_RETRY
findtime = $FAIL2BAN_FIND_TIME
bantime = $FAIL2BAN_BAN_TIME
ignoreip = 127.0.0.1/8 $LAN_RANGE
EOF
}

# The blocklist lives in its OWN nftables table. It only has an input hook with policy accept, so
# it drops listed sources and does nothing else. Docker, Incus and ufw keep their own tables and
# chains untouched, and forwarded container traffic is not affected. Priority -10 runs it early.
nft_content() {
  local elements
  elements="$(printf '%s' "$BLOCKLIST_RANGES" | xargs | sed 's/ /, /g')"
  cat <<EOF
# Managed by MetaService harden-linux.sh
table inet $BLOCKLIST_TABLE
delete table inet $BLOCKLIST_TABLE
table inet $BLOCKLIST_TABLE {
	set blocked_ipv4 {
		type ipv4_addr
		flags interval
		elements = { $elements }
	}
	chain input {
		type filter hook input priority -10; policy accept;
		ip saddr @blocked_ipv4 drop
	}
}
EOF
}

# Loads the table again at every boot. Stopping it deletes only our table.
blocklist_unit_content() {
  cat <<EOF
# Managed by MetaService harden-linux.sh
[Unit]
Description=MetaService source-range blocklist (own nftables table, input drops only)
DefaultDependencies=no
After=local-fs.target
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$NFT_BIN -f /etc/metaservice-blocklist.nft
ExecReload=$NFT_BIN -f /etc/metaservice-blocklist.nft
ExecStop=-$NFT_BIN delete table inet $BLOCKLIST_TABLE

[Install]
WantedBy=multi-user.target
EOF
}

auto_upgrades_content() {
  cat <<EOF
// Managed by MetaService harden-linux.sh
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
}

# Ubuntu's own 50unattended-upgrades already limits origins to the security pocket (and ESM).
# This file does not widen that. It only forbids reboots and keeps GPU driver packages out.
unattended_content() {
  local pattern
  printf '// Managed by MetaService harden-linux.sh\n'
  printf 'Unattended-Upgrade::Automatic-Reboot "false";\n'
  printf 'Unattended-Upgrade::Package-Blacklist {\n'
  for pattern in $NVIDIA_PACKAGE_PATTERNS; do
    printf '\t"%s";\n' "$pattern"
  done
  printf '};\n'
}

# ---- apply steps -----------------------------------------------------------------------------

pkg_installed() { sys dpkg -s "$1" >/dev/null 2>&1; }

install_package() {
  if pkg_installed "$1"; then
    note "  package $1 already installed"
    return 0
  fi
  note "  installing package $1"
  sys env DEBIAN_FRONTEND=noninteractive apt-get install -y "$1"
}

# After writing the drop-in, ask sshd what it will really use. Fail closed if it cannot say.
verify_effective_ssh() {
  local user_list="$1" effective option
  effective="$(sys_out sshd -T | tr '[:upper:]' '[:lower:]')"
  [ -n "$effective" ] || refuse "sshd -T printed nothing, so I cannot prove the new settings are active."
  for option in "passwordauthentication no" "kbdinteractiveauthentication no" "permitrootlogin no" "allowusers $user_list"; do
    printf '%s\n' "$effective" | grep -Fxq "$option" \
      || refuse "sshd would still use a different value than '$option' (another file wins?). Undoing."
  done
}

step_ssh() {
  local user_list="$1"
  note "[SSH] key-only login drop-in"
  install_managed_file "$SSH_DROPIN" 644 "$(ssh_dropin_content "$user_list")"
  [ "$FILE_CHANGED" = 1 ] || return 0
  record_after "systemctl reload ssh"
  sys sshd -t || refuse "sshd -t rejected the new configuration. Undoing."
  verify_effective_ssh "$user_list"
  sys systemctl reload ssh
  note "  sshd reloaded. Existing sessions stay open."
}

step_fail2ban() {
  note "[fail2ban] ban repeat SSH failures"
  install_package fail2ban
  install_managed_file "$JAIL_FILE" 644 "$(jail_content)"
  sys systemctl enable --now fail2ban
  [ "$FILE_CHANGED" = 0 ] || sys systemctl reload fail2ban
  [ "$FILE_CHANGED" = 0 ] || record_after "systemctl reload fail2ban"
}

step_blocklist() {
  note "[blocklist] drop listed source ranges (own nftables table '$BLOCKLIST_TABLE')"
  if [ -z "$BLOCKLIST_RANGES" ]; then
    note "  the list is empty, nothing to do"
    return 0
  fi
  have_command nft || install_package nftables
  local changed=0
  install_managed_file "$NFT_FILE" 644 "$(nft_content)"
  changed="$FILE_CHANGED"
  install_managed_file "$BLOCKLIST_UNIT_FILE" 644 "$(blocklist_unit_content)"
  [ "$FILE_CHANGED" = 0 ] || changed=1
  sys nft -c -f "$NFT_FILE" || refuse "nft rejected the blocklist file. Undoing."
  if [ "$changed" = 1 ]; then
    record_undo "systemctl disable --now metaservice-blocklist.service"
    record_after "systemctl daemon-reload"
    sys systemctl daemon-reload
    sys systemctl enable metaservice-blocklist.service
    sys systemctl restart metaservice-blocklist.service
    return 0
  fi
  sys systemctl enable --now metaservice-blocklist.service
}

step_unattended_upgrades() {
  note "[updates] automatic security updates, never a reboot"
  install_package unattended-upgrades
  install_managed_file "$AUTO_UPGRADES_FILE" 644 "$(auto_upgrades_content)"
  install_managed_file "$UNATTENDED_FILE" 644 "$(unattended_content)"
  sys systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
}

# ---- automatic rollback ----------------------------------------------------------------------

schedule_revert() {
  local bin_dir="$STATE_DIR/bin"
  mkdir -p "$bin_dir"
  cp -p "$SCRIPT_DIR/harden-linux.sh" "$SCRIPT_DIR/harden-common.sh" "$bin_dir/"
  sys systemctl stop "$REVERT_UNIT.timer" || true
  sys systemd-run "--unit=$REVERT_UNIT" "--on-active=$AUTO_REVERT_TIMER" \
    "--description=MetaService harden automatic rollback" "$bin_dir/harden-linux.sh" rollback --auto
  touch "$PENDING_MARKER"
  note "Automatic rollback scheduled in $AUTO_REVERT_TIMER. Run 'sudo harden-linux.sh confirm' to keep the changes."
}

cancel_revert() {
  sys systemctl stop "$REVERT_UNIT.timer" || true
  rm -f "$PENDING_MARKER"
}

# ---- messages --------------------------------------------------------------------------------

print_sudo_docker_warnings() {
  local user="$1" files
  say ""
  say "Things I only warn about (not changed):"
  files="$(grep -rEl 'NOPASSWD' "$(host_path /etc/sudoers)" "$(host_path /etc/sudoers.d)" 2>/dev/null || true)"
  if [ -n "$files" ]; then
    say "  - Passwordless sudo is configured in: $(printf '%s' "$files" | tr '\n' ' ')"
    say "    Anyone who gets into that account becomes root. Remove it when you can."
  fi
  if sys_out id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
    say "  - '$user' is in the docker group, which is the same as root on this machine."
  fi
  say "  - Package installs (fail2ban, nftables, unattended-upgrades) are not removed by rollback."
}

print_summary() {
  local user="$1"
  say ""
  say "=== Summary ==="
  say "Log file: $LOG_FILE"
  say "Backups:  $STATE_DIR"
  say ""
  say "Verify now (from ANOTHER terminal, do not close this one):"
  say "  ssh -o BatchMode=yes -p $PUBLIC_PORT $user@$PUBLIC_ADDRESS true                 # your key login must still work"
  say "  ssh -o BatchMode=yes -o PreferredAuthentications=password -o PubkeyAuthentication=no -p $PUBLIC_PORT $user@$PUBLIC_ADDRESS true"
  say "      -> must say: Permission denied (publickey)."
  say "On this machine:"
  say "  sudo sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|allowusers)'"
  say "  sudo fail2ban-client status sshd"
  say "  sudo nft list table inet $BLOCKLIST_TABLE"
  say "  systemctl is-enabled unattended-upgrades apt-daily-upgrade.timer"
  say ""
  if [ "$CHANGES_MADE" = 1 ]; then
    say "NEXT: if the key login works, run: sudo $0 confirm"
    say "If you do nothing, everything is rolled back automatically in $AUTO_REVERT_TIMER."
    return 0
  fi
  say "Nothing needed changing. Everything was already in place."
}

# ---- commands --------------------------------------------------------------------------------

run_apply() {
  local user user_list extras
  require_root
  detect_machine
  user="$(invoking_user)"
  extras="$(validated_user_list "$EXTRA_ALLOWED_USERS")"
  user_list="$user${extras:+ $extras}"
  validate_blocklist "$BLOCKLIST_RANGES"
  have_command systemd-run || refuse "systemd-run is missing, so I cannot schedule the safety rollback. Nothing was changed."
  if [ -f "$PENDING_MARKER" ]; then
    refuse "The previous apply is still waiting. Run 'confirm' or 'rollback' first."
  fi
  require_key_login_safe "$user"
  mkdir -p "$STATE_DIR"
  trap 'apply_exit_trap $?' EXIT
  log_line "apply started by $user"
  install_needed_packages
  step_blocklist
  step_fail2ban
  step_unattended_upgrades
  step_ssh "$user_list"
  [ "$CHANGES_MADE" = 0 ] || schedule_revert
  APPLY_FINISHED=1
  trap - EXIT
  print_sudo_docker_warnings "$user"
  print_summary "$user"
}

# Slow package work happens before any config is touched, so the rollback timer never runs mid-install.
install_needed_packages() {
  note "[packages] installing what is needed first"
  have_command nft || install_package nftables
  install_package fail2ban
  install_package unattended-upgrades
}

run_updates() {
  local answer="$1"
  require_root
  detect_machine
  say "This runs: apt-get update && apt-get full-upgrade"
  say "WARNING: packages such as docker, containerd, incus and the NVIDIA driver may restart containers or"
  say "stop GPU jobs. Tell the people using this machine first. This script will NOT reboot."
  if [ "$answer" != yes ]; then
    say "Nothing done. Run again with --yes when you are ready."
    return 0
  fi
  mkdir -p "$STATE_DIR"
  log_line "updates started"
  sys apt-get update
  sys env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold full-upgrade
  note "Updates installed."
  if [ -e "$(host_path /var/run/reboot-required)" ]; then
    say "A REBOOT IS NEEDED to finish (new kernel or libraries). Reboot yourself when GPU jobs can stop:  sudo reboot"
    return 0
  fi
  say "No reboot is needed."
}

# ---- check (read-only) -----------------------------------------------------------------------

file_state() {
  local target="$1" wanted="$2"
  if [ ! -f "$target" ]; then
    printf 'missing'
  elif [ ! -r "$target" ]; then
    printf 'unreadable without sudo'
  elif [ "$(cat "$target")" = "$wanted" ]; then
    printf 'in place'
  else
    printf 'differs'
  fi
}

# "change it" when the state is not "in place".
apply_action() { if [ "$1" = "in place" ]; then printf 'nothing'; else printf 'write it'; fi; }

check_ssh() {
  local files password dropin_state
  files="$(ls "$SSH_DIR"/sshd_config.d/*.conf 2>/dev/null || true) $SSH_DIR/sshd_config"
  # shellcheck disable=SC2086  # the file list is words on purpose
  password="$(first_sshd_value PasswordAuthentication $files)"
  dropin_state="$(file_state "$SSH_DROPIN" "$(ssh_dropin_content "${CHECK_USER}${EXTRA_ALLOWED_USERS:+ $EXTRA_ALLOWED_USERS}")")"
  print_row "SSH password login" "$password" "set to no"
  print_row "SSH drop-in $SSH_DROPIN_NAME" "$dropin_state" "$(apply_action "$dropin_state")"
  [ ! -e "$SSH_DIR/sshd_config.d/50-cloud-init.conf" ] || print_row "cloud-init ssh file" "present (read after 00-)" "stays, but 00- wins"
}

check_keys() {
  local keys count=0 home
  home="$(user_home "$CHECK_USER")"
  keys="$home/.ssh/authorized_keys"
  if [ -r "$keys" ]; then
    count="$(grep -v '^[[:space:]]*#' "$keys" | grep -Ec "$SSH_KEY_PATTERN" || true)"
  fi
  print_row "SSH keys for $CHECK_USER" "$count usable key(s)" "needs at least 1 to apply"
}

check_fail2ban() {
  local installed=no jail
  pkg_installed fail2ban && installed=yes
  jail="$(file_state "$JAIL_FILE" "$(jail_content)")"
  print_row "fail2ban package" "installed: $installed" "$([ "$installed" = yes ] && echo nothing || echo install)"
  print_row "fail2ban sshd jail" "$jail" "$(apply_action "$jail")"
}

check_blocklist() {
  local nft_state unit_state
  nft_state="$(file_state "$NFT_FILE" "$(nft_content)")"
  unit_state="$(file_state "$BLOCKLIST_UNIT_FILE" "$(blocklist_unit_content)")"
  print_row "blocklist rules" "$nft_state" "$(apply_action "$nft_state")"
  print_row "blocklist boot unit" "$unit_state" "$(apply_action "$unit_state")"
}

check_unattended() {
  local auto extra
  auto="$(file_state "$AUTO_UPGRADES_FILE" "$(auto_upgrades_content)")"
  extra="$(file_state "$UNATTENDED_FILE" "$(unattended_content)")"
  print_row "auto security updates" "$auto" "$(apply_action "$auto")"
  print_row "no auto reboot / GPU pins" "$extra" "$(apply_action "$extra")"
}

run_check() {
  CHECK_USER="${SUDO_USER:-$(id -un)}"
  say "harden-linux check (read-only). Nothing is changed."
  say "Blocklist: $BLOCKLIST_RANGES"
  say ""
  print_header
  check_ssh
  check_keys
  check_fail2ban
  check_blocklist
  check_unattended
  say ""
  say "To change things: sudo $0 apply --confirm-key-login"
}

# ---- entry point -----------------------------------------------------------------------------

usage() {
  say "Usage: harden-linux.sh [check|apply|confirm|rollback] [--confirm-key-login] [--extra-users \"a,b\"]"
  say "       harden-linux.sh --updates [--yes]"
}

main() {
  local command=check updates=0 answer=no automatic=0
  while [ $# -gt 0 ]; do
    case "$1" in
      check | apply | confirm | rollback) command="$1" ;;
      --confirm-key-login) KEY_LOGIN_TESTED=1 ;;
      --extra-users) shift; EXTRA_ALLOWED_USERS="${1:?--extra-users needs a value}" ;;
      --updates) updates=1 ;;
      --yes) answer=yes ;;
      --auto) automatic=1 ;;
      -h | --help) usage; return 0 ;;
      *) usage >&2; return 2 ;;
    esac
    shift
  done
  setup_environment
  [ "$automatic" = 0 ] || log_line "automatic rollback timer fired"
  if [ "$updates" = 1 ]; then
    [ "$command" = check ] || refuse "--updates is a separate step. Run it on its own, not together with $command."
    run_updates "$answer"
    return
  fi
  case "$command" in
    check) run_check ;;
    apply) run_apply ;;
    confirm) require_root; run_confirm ;;
    rollback) require_root; run_rollback ;;
  esac
}

main "$@"
