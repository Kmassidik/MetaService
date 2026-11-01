# Hardening scripts

Two scripts that you run yourself with `sudo` on each machine. They are written to be read before
they are run. Nothing here is ever run by an assistant, and nothing reboots a machine.

| File | For |
|---|---|
| `harden-linux.sh` | DGX Spark, RTX 5090 PC (Ubuntu or Debian) |
| `harden-mac.sh` | Mac Mini, Mac Studio (macOS) |
| `harden-common.sh` | Shared helpers. Copy it together with the script, same folder. |

Tests: `python3 scripts/tests/test_harden.py` (no root, no real system; see the end).

## What they do

**harden-linux.sh `apply`**

1. SSH: writes `/etc/ssh/sshd_config.d/00-metaservice-hardening.conf` (no passwords, no keyboard-interactive,
   no root login, `AllowUsers` = you plus `--extra-users`, `MaxAuthTries 3`, `LoginGraceTime 20`,
   `MaxStartups 10:30:60`). The `00-` name matters: sshd keeps the first value it reads, so the cloud-init
   file can no longer turn passwords back on. It runs `sshd -t`, asks `sshd -T` what is really active, then
   `systemctl reload ssh`. Open sessions stay open.
2. fail2ban: installs it, jail `sshd` with 4 tries in 10 minutes, ban 1 hour, your LAN never banned.
3. Blocklist: the ranges at the top of the script are dropped on INPUT, in their own nftables table
   `metaservice-blocklist` (hook input, priority -10, policy accept), reloaded at boot by
   `metaservice-blocklist.service`. Docker, Incus and ufw rules are not touched, forwarded container
   traffic is not affected, and nothing is flushed.
4. Unattended upgrades: turned on for what Ubuntu already allows (security pocket), with
   `Automatic-Reboot "false"` and NVIDIA/CUDA packages kept out so a driver never changes under a GPU job.
5. Prints (does not change) warnings about passwordless sudo and docker group membership.

**harden-linux.sh `--updates --yes`** is a separate step: `apt-get update` and `full-upgrade`. It never
reboots. It tells you when a reboot is needed. Warning: Docker, Incus and NVIDIA package upgrades can restart
containers or stop GPU jobs. Tell Luca first.

**harden-mac.sh `apply`**

1. SSH: the same drop-in (without `MaxStartups`), validated with `sshd -t` and `sshd -T`. macOS starts a new
   sshd for each connection, so there is nothing to reload; the next login uses the file.
2. Application firewall: first adds `metaservice-root`, `metaservice-agent`, `cloudflared` and `wireguard-go`
   to the allow list (when found in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/local/sbin`,
   `/opt/metaservice/bin`; set `FIREWALL_EXTRA_APPS="/full/path ..."` for others), then turns on allow-signed,
   stealth mode and the firewall. If a prompt asks about a helper, choose Allow.
3. `--screen-sharing-off` (not done by default): turns off Screen Sharing and Remote Management. The Studio's
   owner uses Screen Sharing through an SSH tunnel, so do not use this flag there unless asked.
4. Prints (does not do) the software update and FileVault advice.

## What they do NOT do

No reboot. No ufw enable, no default-deny, no table flush. No Docker or Incus restart. No change to
the MetaService helper or parent. No software update (except `--updates --yes` on Linux). No secrets are read or written.

## Safety design

- `check` (default) only reads. It is safe to run without sudo.
- `apply` needs sudo from your own account (`SUDO_USER`), and refuses unless: your `~/.ssh/authorized_keys`
  has a real key; your home, `.ssh` and the key file belong to you and are not writable by others; and you
  pass `--confirm-key-login` to say you tested a key login from a second terminal.
- Each file is backed up to `/var/backups/metaservice-harden/<time>/` (Linux) or
  `/var/db/metaservice-harden/<time>/` (Mac) with a manifest. Log: `/var/log/metaservice-harden.log`.
- An automatic rollback runs 5 minutes after `apply` unless you run `confirm`.
  Linux uses `systemd-run --on-active=5min`; the Mac uses a detached `sleep` job (a Mac reboot cancels it).
- If `apply` fails half way it undoes itself.
- A second `apply` after `confirm` changes nothing and makes no new backup.
- Blocklist ranges are checked with a strict pattern (no leading zeros, aligned, /8 to /32) and may not
  overlap your LAN `192.168.0.0/24` or loopback. One bad entry stops everything.
- Package installs (fail2ban, nftables, unattended-upgrades) are not uninstalled by rollback.

## Order

Spark, then RTX PC, then Mac Mini, then Mac Studio. One machine at a time. Do not start the next until the
previous one is confirmed and the Security page is green.

| Machine | Script | User | Public port | Notes |
|---|---|---|---|---|
| DGX Spark | `harden-linux.sh` | `lucacadalora` | 1001 | already key-only; the value is fail2ban, the blocklist and updates |
| RTX 5090 PC | `harden-linux.sh` | `luca` | 1003 | passwords are on now; cloud-init file is overridden by `00-` |
| Mac Mini | `harden-mac.sh` | `lora` | 1002 | passwords on, firewall off; the parent runs here, see the warning below |
| Mac Studio | `harden-mac.sh` | `lucacadalora` | 22 | do not use `--screen-sharing-off` unless asked |

The MetaService parent connects as these users. If another account logs in over SSH, add it with `--extra-users`.

## Pre-flight checklist (every machine)

1. Tell Luca. Choose a time window when nobody needs the machine (and, for the Mini, nobody uses the panel).
2. Know how to reach the machine's console (keyboard and screen, or the router/KVM), in case SSH breaks.
3. Open SSH session A and keep it open all the time.
4. From a second terminal B, test a key-only login: `ssh -o PasswordAuthentication=no -o PreferredAuthentications=publickey -p <port> <user>@<address> true`.
5. Copy the folder `scripts/harden/` to the machine (through your usual way, not from here).
6. In session A run `./harden-linux.sh check` (or `harden-mac.sh check`) and read the table.

## Run (in session A)

```bash
# Linux
sudo ./harden-linux.sh apply --confirm-key-login              # add --extra-users "name" if needed
# Mac
sudo ./harden-mac.sh apply --confirm-key-login
```

You have 5 minutes. The script prints the verification commands with your user filled in.

## Verify (from terminal B and this laptop)

1. Key login still works: `ssh -o BatchMode=yes -p <port> <user>@<address> true` returns without error.
2. Passwords are refused: `ssh -o BatchMode=yes -o PreferredAuthentications=password -o PubkeyAuthentication=no -p <port> <user>@<address> true`
   must end with `Permission denied (publickey).`
3. Linux: `sudo fail2ban-client status sshd`, `sudo nft list table inet metaservice-blocklist`.
   Mac: `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` and `--getstealthmode`.
4. MetaService still reaches the machine: open the machine in the panel and check that it is online.
   On a Mac with the firewall newly on, check that the helper, `cloudflared` and WireGuard still connect.
5. Open the **Security page**: the rows for password login, fail2ban and firewall should turn green for this machine.
6. Only now run `sudo ./harden-<linux|mac>.sh confirm`. If you do nothing, everything rolls back by itself.

Then run `--updates --yes` on Linux when the GPU jobs can stop, and reboot yourself afterwards.

## Rollback

`sudo ./harden-linux.sh rollback` (or `harden-mac.sh rollback`) restores the files saved by the last apply, removes
files that did not exist before, stops the blocklist unit, reloads ssh, and on a Mac puts the firewall switches and
Screen Sharing back the way they were. If you are locked out and cannot get in, wait 5 minutes for the automatic
rollback, or use the console and run the same command.

## Tests

`python3 scripts/tests/test_harden.py` runs both scripts with `HARDEN_ROOT` (every path under a temp folder) and
`HARDEN_DRY_COMMANDS=1` (commands are recorded, not run). `HARDEN_ROOT` without dry mode, or dry mode without
`HARDEN_ROOT`, is refused by the scripts. Not covered by tests: real sshd, nft, fail2ban, apt, socketfilterfw,
launchctl and systemd-run behaviour. Review the first run with `check` and keep session A open.
