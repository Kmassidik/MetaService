# join-share: the contract

A PC anywhere joins the MetaService panel with one command. This file is the single agreement between the three parts of the feature: the **hub** (Rust, `hub/`), the **join script** (POSIX sh, `script/`) and the **admin page** (`web/`). The product idea is in `docs/PRD-share-machine.md` (local file). **Nothing outside `join-share/` is edited.** The only contact with the existing parent is the one table row described in section 6.

## 1. Words

- **hub**: the `join-share` program on the Mac Mini. It owns the WireGuard network and the join flow.
- **far PC** / **spoke**: the computer that joins.
- **link**: a one-time code in the join command, valid 15 minutes, used once.
- **approval code**: 6 digits shown by the far PC's terminal and typed by the admin.
- **helper**: the existing `metaservice-agent` (Swift on Mac, Rust on Linux). It is not changed.

## 2. Addresses and ports

| What | Value | Setting (env) |
|---|---|---|
| WireGuard network | `10.77.0.0/24` | `JOIN_SHARE_NET` |
| Hub address on it | `10.77.0.1` | |
| Far PC addresses | `10.77.0.2` upward, lowest free, one `/32` each | |
| WireGuard UDP port on the Mini | `51830` | `JOIN_SHARE_WG_PORT` |
| Hub public endpoint written into far PCs (host:port) | none by default; must be set | `JOIN_SHARE_ENDPOINT` |
| Public listener (join script, register, status, helper download) | `127.0.0.1:9110`, reached from the internet through a hostname on the Cloudflare tunnel | `JOIN_SHARE_PUBLIC_BIND` |
| Public base URL written into the join command | none by default; must be set (for example `https://join.ruvio.site`) | `JOIN_SHARE_PUBLIC_URL` |
| Admin listener (page and admin API) | `127.0.0.1:9111` | `JOIN_SHARE_ADMIN_BIND` |
| Parent's agent listener a far PC reports to | `http://10.77.0.1:9102` | `JOIN_SHARE_PARENT_URL` |
| Helper port on a far PC | `9101`, bound to its WireGuard address only | |
| Hub state folder | `join-share/state/` (git-ignored): `hub.sqlite3`, `wg-hub.conf`, `admin.key` (mode 600) | `JOIN_SHARE_STATE` |
| Parent database (the one row insert, section 6) | path of the parent's `root.sqlite3` | `JOIN_SHARE_PARENT_DB` |
| Folder with the helper builds | the parent's existing `agent-builds-dir` (`<dir>/<os>-<cpu>/metaservice-agent`) | `JOIN_SHARE_BUILDS_DIR` |

OS words: `mac`, `linux`, `windows`. CPU words: `arm64`, `x86_64`. A `(os, cpu)` pair is **supported** when `<builds>/<os>-<cpu>/metaservice-agent` exists and `os` is `mac` or `linux`; `windows` is always "coming soon".

## 3. The flow

```
admin page ── POST /admin/links ─────────────► hub: link made (15 min)
admin copies the command  ─────────────────► sends it to the far PC's owner
far PC: curl -fsSL "<public_url>/j/<link>?os=<os>&cpu=<cpu>" | sh
   script: checks os/cpu match, lists what is missing, asks to continue
   script: ONE sudo block (packages, WireGuard interface, start at boot)
   script: makes a WireGuard key pair on the machine
   script ── POST /j/<link>/register ───────► hub: pending machine + 6-digit code
   script shows the code, then polls GET /j/<link>/status?pending=<id>&secret=<s>
admin page: types the code, presses Approve (name, share limits shown, can lower)
   hub: picks 10.77.0.x, adds the WireGuard peer, inserts the enrollment row
   status → approved with everything the script needs
   script: brings the WireGuard interface up, downloads the helper (checked against sha256),
           runs `metaservice-agent enroll` then `run`, installs the start-at-boot entry
parent: heartbeat arrives from 10.77.0.x → the machine is ONLINE in Machines
```

## 4. Public HTTP (listener 9110)

All answers are JSON except the script. An unknown, expired or used link gets `404 {"error":"unknown_link"}` and nothing else (no hint which). Per-IP rate limit on every route; a body limit of 16 KiB; no cookies.

| Route | What |
|---|---|
| `GET /j/<link>?os=&cpu=` | The join script (`text/x-shellscript`), with the link, public URL, os and cpu filled in. Does not use the link up. `400` if the pair is not supported, with a plain reason in JSON. |
| `POST /j/<link>/register` | Body `{"wg_public_key": "<44 chars base64>", "os": "...", "cpu": "...", "hostname": "...", "share": {"cores": n, "ram_mb": n, "disk_gb": n}}`. Uses the link up. Makes a pending machine. Reply `{"pending": "<id>", "secret": "<random>", "code": "123456", "expires_in": 900}`. |
| `GET /j/<link>/status?pending=<id>&secret=<s>` | `{"state":"pending"}` or `{"state":"refused"}` or `{"state":"expired"}`, or when approved: `{"state":"approved","wireguard":{"address":"10.77.0.2/32","hub_public_key":"...","endpoint":"host:port","allowed_ips":"10.77.0.1/32","keepalive":25},"machine":{"name":"...","enrollment_token":"...","parent_url":"http://10.77.0.1:9102","helper_bind":"10.77.0.2","helper_port":9101},"download":{"url":"<public_url>/dl/<os>-<cpu>/metaservice-agent?pending=<id>&secret=<s>","sha256":"<hex>"}}`. The enrollment token is given **once**: a second approved read returns the state without `machine.enrollment_token`. |
| `GET /dl/<os>-<cpu>/metaservice-agent?pending=&secret=` | The helper file, only for an approved pending machine of that `(os, cpu)`. |

The 6-digit code is stored only as a hash, expires with the pending machine (15 minutes), and allows 5 wrong tries, then the pending machine is refused.

## 5. Admin HTTP (listener 9111)

Every route except `GET /` needs the header `X-Admin-Key: <contents of admin.key>`; compared in constant time. `GET /` serves the page, which asks for the key once (it can be given in the URL fragment `#key=...`, never in a query string) and keeps it in memory only.

| Route | What |
|---|---|
| `POST /admin/links` | Body `{"os":"mac","cpu":"arm64"}`. Reply `{"link": "...", "expires_at": "...", "command": "curl -fsSL \"<public_url>/j/<link>?os=mac&cpu=arm64\" \| sh"}`. `400` for an unsupported pair. |
| `GET /admin/supported` | The table of the three buttons: `[{"os":"mac","cpus":[{"cpu":"arm64","state":"ready"},{"cpu":"x86_64","state":"untested"}]},{"os":"linux",...},{"os":"windows","cpus":[...,"state":"soon"]}]`. States: `ready`, `untested` (a build exists but is not proven), `missing` (no build), `soon`. |
| `GET /admin/pending` | Pending machines: id, hostname, os, cpu, share asked, created, expires, tries left. **Never the code.** |
| `POST /admin/pending/<id>/approve` | Body `{"code":"123456","name":"my-mac","share":{...lowered or equal...}}`. Wrong code: `403 {"error":"wrong_code","tries_left":n}`. Success: peer added, address given, enrollment row inserted, `{"address":"10.77.0.2"}`. Name taken: `409`. |
| `POST /admin/pending/<id>/refuse` | Marks it refused. |
| `GET /admin/peers` | Joined machines: name, address, public key (first 8 chars), os, cpu, last handshake seconds ago. |
| `DELETE /admin/peers/<name>` | Removes the WireGuard peer, frees the address. (Removing the machine itself stays in the existing panel.) |

## 6. The one contact with the existing parent

The hub inserts **one row per approval** into the parent's `enrollments` table, exactly as the parent's own `EnrollmentStore.create` does (read it: `control-plane/arm64/Sources/RootStore/Machines/EnrollmentStore.swift`):

```sql
INSERT INTO enrollments (token_hash, machine_name, created_at, expires_at, expected_ip)
VALUES (sha256_hex(token), name, now_unix, now_unix + 900, '10.77.0.x');
```

`token` is random (32 bytes, hex); `expected_ip` pins the enrollment to the far PC's WireGuard address; the table is otherwise only read. The hub opens the database with a busy timeout and never writes any other table. The helper then runs `enroll --root <parent_url> --name <name> --enrollment-token-file ...` as it does for every machine, and the parent records the machine with `ip` = the address it sees (`10.77.0.x`) and reaches the helper at `10.77.0.x:9101` like a machine on the office network.

How the parent's listener `9102` becomes reachable at `10.77.0.1` without changing parent code (a `pf` redirect, or `ROOT_AGENT_BIND`) is decided by the spike in `ops/`, not here.

## 7. The WireGuard side

- Hub: `wg-quick` with a generated `wg-hub.conf` (rebuilt from the database at start). Peers are added live with `wg set` and recorded in the database; the database is the truth.
- Far PC: `wg-quick` with a config the script writes: `[Interface] PrivateKey, Address = <addr>/32` and `[Peer] PublicKey = hub, Endpoint, AllowedIPs = 10.77.0.1/32, PersistentKeepalive = 25`. Only the hub address is routed through it.
- Hub firewall (`pf`, anchor `com.metaservice.joinshare`): from the WireGuard interface, **block everything** except TCP to `10.77.0.1:9102`; pass out to the peers so the parent reaches `<peer>:9101`. No peer-to-peer. IP forwarding stays off.

## 8. The join script (what `script/` must do)

POSIX `sh`, no bashisms, `set -eu`, every value quoted. It must:
1. Print what it will do, ask `Continue? [y/N]` reading from `/dev/tty` (so it works through `curl | sh`), and stop on anything but `y`.
2. Check `uname -s` and `uname -m` against the `os`/`cpu` in the command; stop with a plain message on a mismatch.
3. Print a check list (found / missing) for: `wg`, `wg-quick`, `wireguard-go` (Mac only), the WireGuard kernel support (Linux), `curl`, the helper, and (Linux, optional) Incus. Install only what is missing.
4. Put every step that needs root into **one** block that is printed first and run with a single `sudo` (Homebrew itself runs as the normal user). The script never reads or stores a password.
5. Generate the key pair on the machine (`wg genkey | tee … | wg pubkey`), private key mode 600, never sent anywhere.
6. Call register, print the 6-digit code large, and poll status every 3 seconds up to 15 minutes; handle `refused` and `expired` with a plain message.
7. On approved: write the WireGuard config, bring the interface up, download the helper, verify its sha256, run `enroll`, install and start the helper (systemd user service with `enable-linger` in the sudo block on Linux, a LaunchAgent on Mac) bound to the machine's WireGuard address.
8. Make `leave` possible: install `~/.metaservice-join/leave.sh` that stops everything, removes the interface, the service entry, the helper and its folder.
9. Be idempotent: running it again with a fresh link on an already joined machine says so and changes nothing.
10. Work on macOS (Apple silicon) and Fedora Linux (x86_64) first.

## 9. The admin page (what `web/` must do)

One static page served by the hub's admin listener, plain HTML + one JS file + one CSS file, no framework, no build step. It must **reuse the look of the existing panel** (`frontend/src/app.css` and `palette.css` tokens: colours, mono font, buttons `btn`, `tag`, `restable`; read them, copy the values, do not edit them). It shows: the key prompt; **three buttons Mac, Windows, Linux**, then the CPU choices, then the command with a **Copy** button; the pending machines with a code field and **Approve** / **Refuse**; the joined machines with **Remove**. Disabled choices say why in one line. Every state has text (loading, none yet, errors with the plain reason from the API).

## 10. Code rules

`AGENTS.md` at the repo root applies: no nested `if`, about 400 lines per file at most, one job per module, no swallowed errors, no hardcoded secrets (the endpoint, URLs and paths come from the settings above), a test for every feature. Rust crates: `axum` 0.7, `tokio`, `serde`, `serde_json`, `sha2`, `subtle`, `rand` (the versions the Linux helper uses in `agent/linux/Cargo.toml`) and `rusqlite` with `bundled`; nothing else without a reason written in `hub/README.md`.
