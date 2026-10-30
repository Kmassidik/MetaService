# join-share hub

The Rust program on the Mac Mini that owns the WireGuard network and the join flow (design: `../CONTRACT.md`, why: `../../docs/PRD-share-machine.md`).

Two binaries:

- `join-share serve`: public listener + admin listener, runs as the normal user (refuses to run as root). Settings come from the environment only.
- `join-share-root`: the narrow root helper the hub starts with `sudo -n`. Subcommands `up <conf>`, `down`, `add-peer <key> <addr>`, `remove-peer <key>`, `pf-load [iface]`, `pf-unload`, `show`. Optional `--wg <name>`, `--anchor com.apple/<name>`, `--parent-port <n>`. Everything else is refused; every argument is validated.

## Modules (`src/`)

| Module | Job |
|---|---|
| `config` | environment settings, defaults, "must be set" rules |
| `constants`, `clock`, `crypto`, `error`, `secretfile` | fixed numbers, injectable clock, hashing/base64/hex, JSON errors, mode-600 files |
| `store/` | the hub's own SQLite: links, pending machines, peers |
| `codes` | link ids, 6-digit code (hash only), 5 tries, expiry |
| `peers/` | `WgControl` trait; `sudo` (real), `fake` (tests); `alloc` (network, lowest free address); `hubconf` (config text + validator) |
| `firewall` | pf anchor rules text (pure) |
| `parentdb` | the single `enrollments` INSERT (+ read of machine names); nothing else is written to the parent DB |
| `supported` | os/cpu to the parent's system name, helper files, states ready/untested/missing/soon |
| `script` | the join script (`../script/join.sh` embedded) with `@LINK@ @PUBLIC_URL@ @OS@ @CPU@` replaced |
| `join_flow`, `approval` | register/status/download logic; approve/remove peer |
| `http_public`, `http_admin`, `ratelimit` | axum 0.7 routers (admin page files from `../web/` are embedded), per-IP limit |
| `root_args`, `root_run` | root helper: argument validation, execution |
| `startup`, `state` | first start (keys, state folder), bring-up of interface and firewall |

## Test

On the Mini (never on the laptop): `cd ~/MetaService-join-share/join-share/hub && ~/.cargo/bin/cargo test`.
Unit tests sit in each module; `tests/flow.rs` runs the whole flow in process with a fake `WgControl`, a temp parent DB, a temp builds folder and a moving clock. Nothing here needs WireGuard, sudo or pf; live tests belong in `../ops/`.

## Settings (CONTRACT section 2)

| What | Value | Setting |
|---|---|---|
| WireGuard network | `10.77.0.0/24` (hub at .1) | `JOIN_SHARE_NET` |
| WireGuard UDP port | `51830` | `JOIN_SHARE_WG_PORT` |
| Hub public endpoint written into far PCs (host:port) | must be set | `JOIN_SHARE_ENDPOINT` |
| Public listener | `127.0.0.1:9110` | `JOIN_SHARE_PUBLIC_BIND` |
| Public base URL in the join command | must be set | `JOIN_SHARE_PUBLIC_URL` |
| Admin listener | `127.0.0.1:9111` | `JOIN_SHARE_ADMIN_BIND` |
| Parent listener a far PC reports to (its port is also the pf redirect port) | `http://10.77.0.1:9102` | `JOIN_SHARE_PARENT_URL` |
| State folder (`hub.sqlite3`, `<wg name>.conf`, `admin.key`, `hub.key`) | `state` | `JOIN_SHARE_STATE` |
| Root helper binary | `/usr/local/libexec/join-share/join-share-root` | `JOIN_SHARE_ROOT_HELPER` |
| Parent database (`root.sqlite3`) | must be set | `JOIN_SHARE_PARENT_DB` |
| Helper builds folder (`metaservice-agent-<system>`) | must be set | `JOIN_SHARE_BUILDS_DIR` |
| Mac helper file (`darwin-arm64`) | none (then Mac arm64 is "missing") | `JOIN_SHARE_MAC_AGENT` |
| wg-quick config / interface name | `wg-metaservice` | `JOIN_SHARE_WG_NAME` |
| pf anchor (must start with `com.apple/`) | `com.apple/joinshare` | `JOIN_SHARE_PF_ANCHOR` |
| Requests per minute per IP, public listener | `60` | `JOIN_SHARE_RATE_LIMIT` |

The admin key is made on first start in `<state>/admin.key` (mode 600). The hub's WireGuard private key is `<state>/hub.key` (mode 600).

## Crates beyond the allowed list

- `tower` and `http-body-util` (dev-dependencies only): drive the routers in process and read response bodies in `tests/flow.rs`; the Linux helper uses the same two.
- No `base64` crate: a 20-line encoder in `crypto.rs` covers key shapes and test keys.

## Interpretations of the contract

- `pf-load` takes no rules file: the root helper regenerates the rules itself from the validated config copy, so a user-writable file cannot make root load arbitrary rules. The hub passes the real `utunN` it got from `up`.
- `up` copies the config into the root-only `/var/run/join-share/` after validating it (only PrivateKey/Address/ListenPort and PublicKey/AllowedIPs are allowed; no PostUp etc.), and `add-peer` checks the address against the network in that copy. pf marker files live there too.
- The admin page files `/app.js` and `/style.css` are served without the key (the page asks for it).
- Approval stores the (possibly lowered) share in the hub database only; the contract has no other place for it.
- The enrollment token is kept in the hub database until the first approved status read, then cleared.
- Machine names are limited to letters, digits, `.`, `-`, `_` (max 40).
