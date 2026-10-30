# join-share

A PC anywhere joins the MetaService panel with one command, over WireGuard. Built on its own branch and in its own folder: nothing outside `join-share/` is edited (the existing parent, helpers and panel keep working as they are).

- `CONTRACT.md`: the agreement between the parts. Read this first.
- `hub/`: the hub, a Rust program that runs on the Mac Mini (WireGuard peers, links, approval, firewall).
- `script/`: the POSIX `sh` join script the far PC runs, and its tests.
- `web/`: the admin page (three buttons: Mac, Windows, Linux) and its browser test.
- `ops/`: setting up the Mini (`prepare-mini.sh`), the boot jobs, the `pf` rules, and the live tests that need `sudo` and WireGuard.

## State (2026-10-30)

Merged into `main` (2026-10-31); the only file outside this folder that changed is one line in `.gitignore`. The hub runs on the Mini as the boot job `io.metaservice.joinshare` from `~/MetaService/join-share` (it restarts by itself: checked with a forced restart and a kill -9). Settings are in `join-share/state/hub.env` (mode 600, not in git).

| What | How to run it | Result |
|---|---|---|
| Hub unit and whole-flow tests (Rust) | on the Mini: `cd join-share/hub && cargo test` | 59 + 13 pass |
| Join script scenarios (stubs, `sh` and `dash`) | `sh join-share/script/tests/run.sh` (and `TEST_SH=dash`) | 80 of 80 |
| Admin page in a real browser | `bun join-share/web/e2e/admin.e2e.ts` | 30 of 30 |
| Real WireGuard and firewall on the Mini (two Linux containers as far PCs) | on the Mini: `sh join-share/ops/live/wg-lab.sh` | 10 of 10 |
| The whole join: real script in a container, real hub, a throw-away parent, the real linux-arm64 helper | on the Mini: `sh join-share/ops/live/join-e2e.sh` | 22 of 22 |

Not tried on real machines yet: the macOS path of the script (stubs only) and a real Fedora laptop. `RUNBOOK.md` lists what is needed to go live.
The live tests use two containers named `jstest-a` and `jstest-b` (Ubuntu with WireGuard tools); they are kept between runs and only ever stopped.
