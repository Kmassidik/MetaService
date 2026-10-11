# CLAUDE.md — MetaService

## SSH to the Mac Studio (`ssh kurnia-pub`)

Too many SSH connections in a short time are seen as a brute-force attack and get blocked.

- **At most 2 SSH connections per session.** Not 2 at a time: 2 in total.
- Put many steps in one script and run it in one connection. Do not run many small commands.
- Never poll over SSH. Read the job's output file locally, or make one check after a long wait.
- Never retry in a loop. If a connection fails, stop and tell Kurnia.
- Use a long-running job (nohup, or a script that writes a log file) for slow work, then check the log in one connection.
- Hard stop stays: no change on the Mac Studio unless Kurnia says go, and never use or ask for a `sudo` password.
