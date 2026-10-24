# Sandboxes (draft plan)

> **DRAFT for Kurnia to review. Nothing here is built.**
> Three files: this plan, [`api.yaml`](api.yaml) (the API a program calls with a key) and [`helper.yaml`](helper.yaml) (what the Linux helper adds to the Root-Agent contract). Questions for Kurnia are at the end.

## What we want

A program with an API key asks for a computer and gets one in under a second. It's a fresh Linux machine with its own kernel that nobody has used before. The program runs commands in it, moves files in and out, and opens a port at a public address. When its time is up, the machine is gone.

That's what E2B, Daytona and Vercel Sandbox sell, except ours runs on our own machines, through MetaService.

The main users are AI agents. An agent writes code and runs it in a sandbox, so a mistake or a bad script never touches anything else.

## What MetaService has, and what is missing

MetaService already does the hard part of running machines: the parent, a helper on each machine, placement by free room, heartbeats, an SSH tunnel to every machine, the Cloudflare tunnel, and a ledger. What's missing is the sandbox side:

| A sandbox service needs | MetaService today |
|---|---|
| An API for programs, with keys | Panel only (admin login and CSRF) |
| A start in under a second | VMs and containers that live long and take seconds to start |
| Commands and files over the API | Console and SSH keys |
| A public address for each port | The panel's address only |
| An end time, with clean-up by itself | None |
| Safety for code nobody checked | Incus containers share the machine's kernel |
| Usage counted per key | AI tokens only |

## The shape

```
 a program (E2B's SDK, curl, ...)
    │  https://api.<domain>              https://<port>-<sandbox id>.<domain>
    ▼                                     ▼
 Cloudflare: two names on the parent's tunnel
    ▼
 parent (Root)    API keys and limits · placement · records · usage · forwards sandbox traffic
    │  the SSH tunnel it already keeps to each machine
    ▼
 Linux helper     templates and snapshots · end times · events · the way in        (runs as a normal user, as today)
    │  a local socket only the helper's user can open
    ▼
 sandbox runner   Firecracker + jailer · network namespaces, taps, firewall rules   (root, a fixed list of requests)
    │
    ▼
 sandbox = a microVM with its own kernel
    └─ envd (port 49983): runs commands, moves files     └─ the program's own ports
```

- **Parent (Root)** is the front door. It checks the API key and its limits, picks a machine, and keeps the record of every sandbox. It counts usage, and it passes traffic for `<port>-<id>.<domain>` to the right machine over the SSH tunnel it already has.
- **The Linux helper** runs the sandboxes with [Firecracker](https://github.com/firecracker-microvm/firecracker), a microVM program made for this job (AWS Lambda and E2B run on it). The helper keeps the templates and snapshots, the end times, the events and the way into each sandbox.
- **The sandbox runner** is a small root service on the same machine. Today the helper runs as a normal user and reaches Incus through the `incus-admin` group. But Firecracker's jailer, network namespaces, tap devices and firewall rules need root. So the runner does only those steps, from a fixed list of requests, on a local socket that only the helper's user can open. It is the same Rust program in another mode, and `setup --yes` installs it, since that step already runs as root.
- **Inside each sandbox** is a small daemon that runs commands and moves files. We use E2B's `envd` (Apache-2.0), so E2B's SDKs work unchanged.
- **Cloudflare** carries two names to the parent's tunnel: one for the API and a wildcard for the sandboxes.

Sandboxes are a new thing next to VMs and containers, not another kind of workload. There will be many of them, they live for minutes, and programs make them, not people. So they get their own routes, their own list and their own events. A heartbeat carries only a summary.

## Why Firecracker, not Incus

- **An Incus container** shares the machine's kernel. With one kernel bug, code in a sandbox owns the machine. That rules it out for code nobody checked.
- **An Incus VM** (QEMU) is safe, but it boots firmware and a whole system. That takes seconds and adds hundreds of MB to each one.
- **Firecracker** boots a kernel straight away, with only the devices a sandbox needs. It can also start a new sandbox from a saved snapshot of one that is already up, with its memory and running programs. E2B says its sandboxes start in about 150 ms this way.
- Firecracker is written in Rust, like the Linux helper, and it's Apache-2.0.
- **What it can't do:** GPUs (it has no PCI passthrough) and Macs. Neither is in v1. GPU sandboxes would later use Cloud Hypervisor, which can pass a GPU through.

VMs and containers stay on Incus as they are.

## How a sandbox starts fast

1. **Template build** (once per template, on each machine). The image becomes a disk and boots in Firecracker. The daemon and the template's `start` command come up. The helper saves that moment as a snapshot: memory, device state and disk.
2. **Create.** The new sandbox gets a copy-on-write copy of the template's disk, which is instant on a filesystem with reflinks such as XFS. Firecracker starts from the snapshot and loads memory lazily: it reads only the pages the sandbox touches. Then the helper hands the sandbox over, as E2B's own orchestrator does:
   - it writes the sandbox's id and a hash of its access token into Firecracker's metadata service;
   - it calls envd's `/init` from the machine with the token, the environment variables, the time, and the default user `user` (without that, commands run as root).

   Every `/init` must carry the token, resume included: one without it removes the token and leaves the sandbox open.
3. **Addresses.** Every clone of one snapshot thinks it has the same IP address. So each sandbox gets its own network namespace where that address is the same, and the machine maps it to a unique one. This follows Firecracker's [network for clones](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/network-for-clones.md) guide.
4. **Randomness.** Clones also share everything else that was in memory. The guest kernel reseeds its randomness by itself on resume (VMGenID, Linux 5.18 and later; see Firecracker's [snapshot notes](https://github.com/firecracker-microvm/firecracker/blob/main/docs/snapshotting/snapshot-support.md)). Anything else meant to be unique is made fresh at each start or never baked into a template: `/etc/machine-id`, SSH host keys, tokens. On ARM this reseed needs a guest kernel 6.10 or later (or a backport). That's one more reason to start on the x86 PC.
5. **Warm pool, only if needed.** If restore alone is not fast enough, a few sandboxes per popular template wait ready. We measure first.

Firecracker restores a snapshot only on the same CPU, the same host kernel and the same Firecracker version it was made on. So templates are built on each machine, and a host kernel or Firecracker update means rebuilding them. Firecracker also asks for cgroups v2 hosts: restores are slow on v1.

**Targets (not measured yet):** a median create under 300 ms at the helper, and under 1 s end to end for a program through Cloudflare.

## Safety

- **Isolation.** Every sandbox is its own microVM with its own kernel. Firecracker's `jailer` runs each one in a chroot, as its own unprivileged user, with cgroups for CPU and memory, and Firecracker adds its seccomp filters.
- **Disk.** Each sandbox has a private copy of its disk. Nothing from the machine is shared into it.
- **Network.** Each sandbox has its own namespace. These are always closed:
  - the office network and every private address range;
  - the machine itself and other sandboxes;
  - link-local and cloud metadata addresses;
  - outgoing mail (port 25).

  Internet access is on or off per sandbox, within the team's limit. There's no IPv6 in v1. Nothing comes in except through the parent's forwarder.
- **Our internet address.** Sandbox traffic leaves through the office's internet connection and address. If someone abuses a sandbox, other sites block that address for everyone. So in v1, keys go only to our own apps, with a bandwidth cap per sandbox. A separate way out (a WireGuard exit on a rented server) comes before keys go to anyone else.
- **Access token.** The daemon inside refuses calls without the sandbox's access token. The parent derives the token from its own secret and the sandbox id (an HMAC, as E2B does), so it can give the same token back on connect without storing it. Only create and connect return it, never get or list.
- **envd's internal routes.** `/init`, `/freeze` and the like are refused from outside. Only the helper calls them, from the machine.
- **Command token.** The Root's command token never reaches a sandbox. It travels in `X-MetaService-Token`, and the helper removes it before the request goes in. `Authorization` passes through untouched, because envd reads it to pick the Linux user.
- **AI keys.** Sandboxes never hold AI keys. A sandbox that needs AI would later get a short-lived capability for the parent's AI proxy, the way the chat does.

## Addresses

E2B's SDKs build every address from one domain. This was checked in their code: JS 2.52.0 (the version Oyenza runs) and the current JS and Python source (2.59.0).
- `https://api.<domain>` for the API;
- `https://<port>-<sandbox id>.<domain>` for everything inside a sandbox. The daemon is port 49983, and the SDK's signed file links use the same form.

There's an older form, one address with the sandbox in `E2b-Sandbox-Id` and `E2b-Sandbox-Port` headers (`E2B_SANDBOX_URL`). The SDKs mark it deprecated, and v1 doesn't serve it.

A sandbox that isn't running, or a port nothing listens on, answers 502, because the SDKs read a 502 from the daemon's `/health` as "not running".

So we need:
- **A domain only for sandboxes,** with a wildcard DNS record and a certificate for `*.<domain>`. Cloudflare's free certificate covers `*.example.com` but not `*.sbx.example.com`. So either the sandboxes get a domain of their own (suggested), or we pay for Cloudflare's certificate for a sub-domain.
- **Both names on the parent's Cloudflare tunnel.** The parent answers the API on one name and forwards the other.

In v1, all sandbox traffic goes through the parent and its SSH tunnel to the machine. That's simple, and it uses what is already there. If traffic grows, each sandbox machine gets its own connector (later).

## The API at a glance

[`api.yaml`](api.yaml) is what a program calls, with `X-API-Key`:

| Call | What it does |
|---|---|
| `POST /v2/sandboxes` | Make a sandbox from a template |
| `GET /v2/sandboxes` | List the team's sandboxes (running, paused, by metadata) |
| `GET /sandboxes/{id}` | One sandbox |
| `DELETE /sandboxes/{id}` | Kill it |
| `POST /sandboxes/{id}/timeout` | Move its end |
| `POST /sandboxes/{id}/pause` | Pause it, memory and all |
| `POST /v2/sandboxes/{id}/connect` | Get it back, resuming it if it's paused |
| `GET /sandboxes/{id}/metrics` | Its CPU, memory and disk readings |

Commands and files are not API routes. They go to the daemon inside, at `49983-<id>.<domain>`, with the sandbox's access token. Anything E2B has that we don't (volumes, snapshots, fork, network rules, template builds) answers 404, or 400 when it arrives as a field. It's never ignored.

[`helper.yaml`](helper.yaml) is what the parent calls on a Linux helper, over the tunnel, with its command token:

| Call | What it does |
|---|---|
| `POST /v1/sandboxes` | Make one and answer when it's ready (synchronous; the parent picks the id, so a retry is safe) |
| `GET`, `DELETE /v1/sandboxes/{id}` | One sandbox; remove it and everything it had |
| `PUT /v1/sandboxes/{id}/end` | Its end time, and kill or pause then |
| `POST /v1/sandboxes/{id}/pause`, `/resume` | Pause and resume |
| `GET /v1/sandboxes/{id}/metrics` | Readings, one every 5 seconds |
| `ANY /v1/sandboxes/{id}/ports/{port}/...` | The way in: HTTP, streams and WebSocket, passed to that port |
| `GET /v1/sandbox-events?after=N` | What happened since change N (ends the helper made itself, running time to count) |
| `GET`, `PUT`, `DELETE /v1/sandbox-templates/...` | Build and remove templates on that machine |

Plus `capabilities.sandbox` and `Facts.sandbox` (room, templates, the last change number) in every heartbeat.

## Teams, keys and limits

- **A team** is whoever uses sandboxes: one of our apps, or a person. A team has limits:
  - how many sandboxes may run at once;
  - the most vCPU, memory and disk per sandbox;
  - the longest end time and the longest life;
  - whether internet access is allowed;
  - which templates it may use.
- **API keys.** A team has one or more keys, so a key can be replaced without a gap. The parent shows a key once and keeps only its SHA-256, as it does with machine tokens.
- **Who makes them.** An operator makes and removes teams and keys in the panel. There's no sign-up in v1.
- **Rate limits and audit.** Each key has rate limits, and every change to a sandbox goes to the audit log.

## Life of a sandbox

- **Running.** A sandbox runs until its end time: 5 minutes after create by default. A program can move the end time, up to the team's longest life.
- **At the end time** it's removed, or paused if it asked for that (`autoPause` in E2B's words).
- **Paused.** Memory and disk are saved on that machine, and it uses no CPU or memory. A resume picks up where it was, on the same machine. Paused sandboxes are kept 7 days (a team setting), then removed.
- **The helper owns the end time.** It acts on it even when the parent is down, so a sandbox never outlives its time.
- **Helper restarts.** After a restart, the helper removes running sandboxes it finds left over (v1). Paused ones survive, since they are files.

## Templates

- **v1 ships one template, `base`:** Ubuntu 24.04 with Python, Node.js, git, curl, the daemon and a user named `user`, whom commands run as. A sandbox from it gets 2 vCPU, 512 MB of memory and a 10 GB disk unless the template or the team says otherwise. `base` is also the SDK's default template name. E2B's other stock names (`code-interpreter-v1`, `desktop`, `mcp-gateway`) come later, if a user needs them.
- **Operators add templates in the panel** with:
  - a base image pinned by digest;
  - steps like a Dockerfile's (RUN, ENV, WORKDIR, USER);
  - an optional `start` command and `ready` check;
  - default sizes.
- **Each sandbox machine builds its own copy,** because a snapshot only starts on the same kind of CPU and the same Firecracker version. The build runs inside a builder sandbox, never on the machine itself, because a step is a program we didn't write.
- **Later:** builds from the API (E2B's `Template.build`).

## Usage

- **The helper counts** each sandbox's running time to the millisecond and reports it in its events.
- **The parent adds it up** per team per day: vCPU-seconds, GB-seconds of memory, and GB-hours of paused disk. This sits next to the token ledger.
- **Room.** In v1, a sandbox's memory counts in full against the machine's room. Lazy memory means sandboxes really use less; we measure that before we let more in.
- **Prices** are not part of this plan.

## Phases

**Phase 0: a machine that can run microVMs** (on site, about an hour)
- PC-RTX-5090: switch SVM on in the BIOS ([issue #4](https://github.com/Kmassidik/MetaService/issues/4)), then check that `ls /dev/kvm` shows a device.
- DGX-Spark (aarch64) already makes VMs, so KVM works there today. Check that `getconf PAGESIZE` says 4096, since Firecracker needs 4K host pages. Firecracker is only tested on AWS Graviton for ARM, so its CPU is a try-and-see. Phase 0 can start there while the PC waits for its BIOS switch.
- Boot Firecracker's getting-started microVM by hand, and note how long it takes.
- Choose the sandbox domain, then add its wildcard DNS record and certificate.

Done when: one office machine boots a microVM by hand, and `https://anything.<domain>` reaches the parent.

**Phase 1: the helper runs a sandbox** (`agent/linux`)
- A new `sandbox` module with Firecracker and jailer (a pinned release with its SHA-256 checked), a pinned guest kernel, and the `base` template booted cold (no snapshot yet).
- The sandbox runner (root, the same program in another mode), installed by `setup --yes`.
- A network namespace per sandbox, with the rules above.
- The daemon (`envd`) inside the sandbox.
- The routes in `helper.yaml`: create, list, get, delete, end, metrics, events and the port route. The helper keeps end times itself and removes leftovers when it starts.
- `capabilities.sandbox` and `Facts.sandbox`.
- A simulated sandbox engine for the contract tests (like `simulated` today), and a smoke script for the real machine.

Done when, on the machine:
- the helper makes a sandbox;
- `echo hi` runs through the daemon;
- a file goes in and comes back out;
- a web server inside answers through the port route;
- the office network and the machine can't be reached from inside;
- the sandbox is gone at its end time, with nothing left: no process, tap, namespace or file.

**Phase 2: fast**
- A snapshot at template build, and every start from it, with lazy memory, network for clones, and a fresh clock and randomness at each start.
- Copy-on-write disks on a reflink filesystem.
- Pause and resume.
- A warm pool, only if it's needed.

Done when:
- 100 creates of `base` in a row on an idle machine come in at a median under 300 ms at the helper, with the slowest 5% under 1 s;
- a paused sandbox resumes with its files and its running programs.

**Phase 3: the API** (parent and panel)
- Teams, keys and limits. Panel pages: API keys, Sandboxes (live list, kill) and Usage.
- The routes in `api.yaml`, plus placement on machines with `capabilities.sandbox`, records, events, the usage ledger and the audit log.
- The two names: the API, and `<port>-<id>`, which is forwarded through the SSH tunnel to the port route (HTTP, streaming and WebSocket).
- `scripts/remote_access`: the two names on the tunnel.

Done when:
- E2B's own SDKs run our check script with only `E2B_DOMAIN` and `E2B_API_KEY` changed. That's JS 2.52.0 (Oyenza's) plus the newest JS and Python, pinned. The script does all of this: create, a command with streamed output, write/read/list files, a signed file link, open a port and fetch it, set the timeout, pause and connect, get info, metrics, list, kill;
- a program with no key, a wrong key, or over its limits is refused.

**Phase 4: templates and first users**
- Templates from the panel, built in a builder sandbox on every sandbox machine.
- Oyenza's task computer moves from E2B to ours with an env change, behind a switch. It already uses E2B's SDK. We make its template (it names its own) from the panel.
- Bandwidth caps per team.

Done when: Oyenza's real tasks run on our sandboxes for a week with no stuck or leaked sandbox.

**Later:**
- template builds from the API;
- GPU sandboxes (Cloud Hypervisor) and Mac sandboxes (Apple `container`);
- a connector on each machine, and a separate internet exit;
- parent restarts that don't drop connections;
- sign-up and billing.

## Not in v1

GPUs, Macs, Windows, sign-up and billing, template builds from the API, volumes that outlive a sandbox, and sandboxes that live longer than a day.

## Questions for Kurnia

Each has a suggestion; any of them can change.

1. **Speak E2B's API, or design our own?** Suggestion: E2B's. Its JS and Python SDKs, docs and tools work on day one, and one of our apps already uses them. The cost is that we follow their changes, so we pin the SDK versions we test and run them in CI.
2. **E2B's `envd` inside the sandbox, or our own daemon?** Suggestion: `envd`. It's Apache-2.0 (E2B's `runtime` repo), it was written for exactly this, it builds for arm64, and the SDK already speaks its protocol. We pin a version (0.10.2 today) and build it ourselves. We report its real version, which also turns on every SDK feature (0.6.4 or later).
3. **Where does the sandbox code live, given that part of it needs root?** Suggestion: the logic goes in the Rust helper as a new module (one program to install and update, the same token, the same tunnel). Only the root steps go in the sandbox runner: the same program in another mode, on a local socket, with a fixed list of requests. The other options are running the helper as root, or sudo rules for exact commands.
4. **Is a synchronous create OK on the helper?** Creating a workload is a long command today (202, then poll). A sandbox should be ready in well under a second, so `POST /v1/sandboxes` answers when it's ready, within 30 seconds. The parent picks the id, so a retry never makes two.
5. **The API in the parent's process, or a separate one?** Suggestion: the same process, in a separate router group with its own guard (API key, no cookies, no CSRF). It answers only on the two sandbox names.
6. **Sandbox traffic through the parent in v1?** Suggestion: yes, with a connector per machine later.
7. **Which machine first?** Suggestion: PC-RTX-5090 once SVM is on, because x86 is Firecracker's best-trodden path. DGX-Spark can already make VMs, so it can do phase 0 now, and it becomes a sandbox machine once Firecracker works on its CPU.
8. **Keys only for our own apps in v1?** Suggestion: yes, until sandbox traffic has its own internet exit.

For Luca: the domain, the BIOS switch, and whether the office connection may carry sandbox traffic at first.

## Risks

- **Abuse from the office's address.** See Safety.
- **E2B changes its API.** We pin SDK versions and test them in CI. It moves fast. The SDKs already create with `POST /v2/sandboxes` and connect with `POST /v2/sandboxes/{id}/connect`. They kill a sandbox whose daemon is older than 0.1.0. And Python reads a create only on exactly 201, with all four required fields.
- **Streams through Cloudflare.** Command output comes back as a stream. The SDK speaks HTTP/2 where it can, and envd itself speaks only HTTP/1.1 (E2B's own proxy reaches it that way too).
  - Cloudflare cuts a proxied response that sends nothing for about 100 seconds. The SDK asks envd for a keepalive every 50 seconds, which should keep streams open.
  - Input streamed to a running program (`StreamInput`) is the part least sure to pass through Cloudflare, the tunnel and the parent over HTTP/1.1.

  Phase 3 checks all of this first.
- **The SDK retries creates by itself** (on 429, 502, 503 and 504, with no idempotency key). So the parent undoes a failed create before it answers. The parent picks the id, so it can always remove what it started.
- **E2B runs its own Firecracker fork,** patched on top of upstream (the fork's source isn't public). We'd use upstream Firecracker. Whether upstream lacks anything E2B relies on is not checked yet.
- **A parent restart drops live connections** (it takes about 40 seconds today). Sandboxes keep running and still end on time, and programs reconnect.
- **A Firecracker or host kernel update makes old snapshots unusable.** Templates can be rebuilt, but paused sandboxes can't be resumed afterwards. So such updates wait until no paused sandbox needs the machine, or the teams are told and their paused sandboxes are removed first.
- **One office.** A power or internet cut takes every sandbox with it.
- **Shared machines.** Sandboxes share the PC with GPU work, so placement has to count both.

## What changes where

- `contract/openapi.yaml`: `capabilities.sandbox`, `Facts.sandbox`, the sandbox routes from `helper.yaml`, and the command type `template_build`. Parent first.
- `contract/sandbox-api.yaml`: the public API, moved from `api.yaml`.
- `agent/linux/src/sandbox/`: Firecracker, jailer, network, store (disks and snapshots), templates, pool, proxy, end times, events, routes and a simulated engine. The runner mode (root) gets its own small request list. `setup.rs` installs the runner, Firecracker and the guest kernel.
- `agent/fake`: the sandbox routes for the conformance suite.
- `control-plane`:
  - `RootCore/Sandboxes`: keys, limits, placement;
  - `RootStore/Sandboxes`: teams, keys, sandboxes, usage;
  - `Root/Sandboxes`: API routes, the forwarder, panel routes.
- `frontend`: the API keys, Sandboxes and Usage pages.
- `scripts/remote_access`: the sandbox names on the tunnel.
