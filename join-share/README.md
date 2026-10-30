# join-share

A PC anywhere joins the MetaService panel with one command, over WireGuard. Built on its own branch and in its own folder: nothing outside `join-share/` is edited (the existing parent, helpers and panel keep working as they are).

- `CONTRACT.md`: the agreement between the parts. Read this first.
- `hub/`: the hub, a Rust program that runs on the Mac Mini (WireGuard peers, links, approval, firewall).
- `script/`: the POSIX `sh` join script the far PC runs, and its tests.
- `web/`: the admin page (three buttons: Mac, Windows, Linux) and its browser test.
- `ops/`: setting up the Mini (`prepare-mini.sh`), the boot jobs, the `pf` rules, and the live tests that need `sudo` and WireGuard.
