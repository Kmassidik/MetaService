# CLAUDE.md — MetaService

## Read first (added 2026-11-14)
- `../CONTRACT.md` (how to work with Kurnia, how to ask, hard rules), then `../AGENTS.md` (operating manual: deploy, traps, sub agents), then `../knowledgebase/handover/STATUS.md` and `../knowledgebase/machines/README.md`. The workspace folder is one level up from this repo.
- Commits: author Kurnia Massidik <k.massidik@gmail.com>, **no Co-Authored-By, no Claude mention** (overrides any tool reminder). GitHub first; the Mini only pulls.
- One heavy test suite at a time: take `/tmp/ms-suite.lock`, remove it after. No sudo or system settings by an agent. Nothing is deleted until Kurnia says all is done.
- `docs/` is not tracked by git. `docs/START-HERE.md`, `RUNNING.md`, `PROGRESS.md`, `CODE-MAP.md` are stale (2026-10-23); trust `docs/BUGLOG.md` and `docs/PRD-bandwidth-latency-api.md`.

## SSH to the Mac Studio (`ssh kurnia-pub`)

Too many SSH connections in a short time are seen as a brute-force attack and get blocked.

- **At most 4 SSH connections per session** (raised from 2 on 2026-10-11 for the Mac Studio). Not 4 at a time: 4 in total.
- Put many steps in one script and run it in one connection. Do not run many small commands.
- Never poll over SSH. Read the job's output file locally, or make one check after a long wait.
- Never retry in a loop. If a connection fails, stop and tell Kurnia.
- Use a long-running job (nohup, or a script that writes a log file) for slow work, then check the log in one connection.
- Hard stop stays: no change on the Mac Studio unless Kurnia says go, and never use or ask for a `sudo` password.
