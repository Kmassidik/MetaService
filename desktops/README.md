# Desktops for agents (plan)

> **Plan for Kurnia to review. Nothing here is built.**
> One file. Questions for Kurnia are at the end. Costs and the business side are in a separate, private plan.

## What we want

An AI agent asks for a computer through an API and gets a Linux desktop with a real, visible Google Chrome. The agent drives the screen (screenshot, click, type, scroll), or drives Chrome itself over CDP. It can give a person a live link to watch, or to take over. A desktop lives for hours or days and keeps its sign-ins.

That's what Orgo sells. Ours would run on Mac-studio, through MetaService.

The first user is Agent Oyen, one of our own agents, which browses with a headless Chrome today. Outside developers would come later, by invite.

This is the Mac side. The sandbox plan ([#5](https://github.com/Kmassidik/MetaService/pull/5)) covers short-lived microVMs on the Linux machines. Both would share one key layer in the parent.

## What exists, and what is missing

The hard part exists: Ruvio's desktop is the core, and MetaService already runs Mac-studio's VMs. What's missing is everything around them.

| A desktop service needs | Today |
|---|---|
| A desktop with a visible Chrome, a live view and screen actions | Ruvio's desktop: Ubuntu 24.04 with Xfce, TigerVNC and noVNC, Google Chrome with its CDP port on loopback, and `desktopd` (screenshot, click, move, type, key and scroll; one caller at a time, with a 60-second lease) |
| A machine that runs VMs with set CPU and RAM | The macOS helper on Mac-studio, on Apple `container` |
| Placement, tunnels and an audit log | The parent |
| An API for programs, with keys | Panel only (admin login and CSRF) |
| Screen actions, commands and files through the host | None yet |
| Live links that are safe to hand out | None yet |
| A firewall on the host that root inside a desktop can't change | None yet |
| Usage counted per key | AI tokens only |

## Why on the macOS helper, not a second Ruvio install

Apple `container` is per macOS user, and each scheduler counts only its own VMs:

- **Same user:** Ruvio's capacity check refuses every create and wake while a VM it doesn't manage is running, such as the helper's `ms-w-ht96lu4`.
- **Different users:** Ruvio would reserve about 28.7 GB and the helper about 27.6 GB. That's about 56 GB promised on a 36 GB machine, and neither sees the other.

The helper already has what a host needs: create, start, stop and delete with set CPU and RAM, setup steps inside a VM, a terminal, commands that are safe to repeat, live state, and placement in the parent. So Ruvio supplies the desktop image and `desktopd`, the helper runs them as a new kind, and the parent gets the key layer.

| Way to build it | Verdict |
|---|---|
| **A.** A second Ruvio install on Mac-studio | Not recommended: the memory clash above, a full Chat and Engine install, and 8–15 more engineer-days to move it into MetaService later |
| **H.** The macOS helper runs Ruvio's desktop | **Recommended:** about the same days to Agent Oyen's first desktop, and 10–20 days cheaper once the sandbox plan shares the key layer |
| **L.** Linux, such as DGX-Spark | Later: more room per machine, but this plan starts on Mac-studio |

Ruvio's code stays in its own private repo. This repo would hold only the desktop image's tag and the fixed setup steps.

## The shape

```
 an agent (Agent Oyen, or a developer's)
    │  https://api.<domain>
    ▼
 Cloudflare: the parent's tunnel
    ▼
 parent (Root)    keys, teams, limits, usage · placement · audit
    │  the SSH tunnel it already keeps to each machine
    ▼
 macOS helper     desktop kind · screen actions · commands and files · port proxy     (Mac-studio)
    │  root firewall runner: a fixed list of requests, rules loaded at boot
    ▼
 desktop = one small VM on its own network
    ├─ Ubuntu 24.04 + Xfce, Google Chrome (CDP on 127.0.0.1:9222)
    ├─ TigerVNC + noVNC: the live view
    └─ desktopd: screen actions

 live view and CDP:  https://<port>-<id>.<domain>  →  a connector on Mac-studio  →  the helper's port proxy
```

- **Control path.** API calls go to the parent, then over the tunnel it already keeps to the helper. That path exists today.
- **Live path.** Live view and CDP are heavy streams, so they don't pass through the parent's machine. A connector on Mac-studio serves `<port>-<id>.<domain>` with short-lived tokens. Agent Oyen reaches its own desktop over a private tunnel, with no public CDP address.
- **After a reboot.** The helper has to start again by itself, the way `./install.sh autostart on` does for the parent.

## Sizes and room

Apple's VMs don't give freed memory back until they restart, so RAM can't be oversold. About 26 GB of Mac-studio's 36 GB is left for desktops, after macOS and host services (about 8 GB) and the worker VM that runs today (2 GB).

| Size | vCPU | RAM | Awake at once | Note |
|---|---:|---:|---:|---|
| Small | 2 | 2 GB | 12 | Too tight: Ruvio measured a 1.76 GiB peak with one agent and 3 tabs |
| Kecil | 2 | 3 GB | 8 | Ruvio's own size |
| Sedang | 2 | 4 GB | 6 | Agent Oyen's size: up to 3 sessions plus a person's own tabs |
| Large | 2 | 8 GB | 3 | Orgo's Medium size; it fills the pool, so at most one |

- **Not measured yet:** Mac-studio's base load with everything running, and one desktop's memory over 72 hours.
- **Stored desktops:** about 7 at Ruvio's 40 GB disk reservation, or about 15 at 20 GB once the ~86 GB of old Tart images are gone.
- **The helper's budget** is the RAM total minus a quarter (27.6 GB here). It should be pinned to a measured number, because other programs on Mac-studio use memory the helper can't see.

## The API at a glance

- **One key for desktops and sandboxes,** accepted as `Authorization: Bearer` and as `X-API-Key`. Keys, teams, limits and usage live in the parent and are built once for both plans.
- **Desktops get Orgo-shaped routes,** such as `POST /v1/computers` and `POST /v1/computers/{id}/click`, so an agent written for Orgo can switch easily. Sandboxes keep the E2B-shaped routes from #5.
- **About 30 routes to start.**

| Feature | What it means | When |
|---|---|---|
| Computers | Create, list, get, start, stop, restart, delete. Two sizes: Kecil and Sedang | Stage 1 |
| Screen actions | Screenshot, click, move, drag, type, key, scroll, wait. Six already exist in `desktopd`; drag and wait are new | Stage 1 |
| Chrome over CDP | Playwright or Puppeteer attach to the desktop's real Chrome with a 5-minute token | Stage 1 |
| Live view | Short-lived links, scoped to view or to control. View-only is enforced on the server, and only allowed sites may embed it | Stage 1 |
| Keys, limits, usage | One key for desktops and sandboxes; usage counted in awake hours | Stage 1 |
| Shell and files | Bash and Python (up to 300 s and 1 MB of output), upload and download. Only after the host firewall exists | Stage 2 |
| MCP server | A thin server over the same routes | Stage 2 |
| SDKs, snapshots, clone, resize, public URLs | Not needed for the first users | Later |
| Windows or macOS desktops | Apple's licence allows 2 macOS VMs per Mac for development or personal use and bans time-sharing. Windows 11's licence bans commercial hosting | No |
| GPU | Apple `container` passes no GPU into a VM, so Chrome draws on the CPU | No |

## Safety

Outside developers would get root inside their desktops. So every wall has to be on the host, where nothing inside a desktop can change it.

| Check | Before Agent Oyen moves (stage 1) | Before outside developers (stage 2) |
|---|---|---|
| Own network | Desktops on their own network, never the default one the helper's other VMs use | One network per account, if tests show that desktops on one network can reach each other |
| Host firewall | A root runner loads the rules after every boot, and a desktop won't start without them. Desktops can't reach the LAN, other private networks, Mac-studio's own services or IPv6 | Plus bandwidth and connection caps per desktop, and port 25 closed |
| Root inside | Agent Oyen's desktop has no shell at all | Developers get root. Every control and all usage data come from the host, never from the guest |
| CDP and live links | CDP over a private tunnel only, with a 5-minute token in a header | Tokens bound to one desktop, a list of allowed sites, and view-only enforced on the server |
| Abuse | Traffic leaves through the office's internet address, as it does today | A kill switch per desktop, a log of who connected where, logged DNS, rules of use, invites |
| Patching | Apple `container` on a release with current security fixes, chosen together, since the helper uses it too | The Chrome image rebuilt within 7–14 days of each Chrome release; isolation tests before every macOS, `container` or firewall change |
| Data at rest | FileVault on, automatic restart on, a UPS, and SSH unlock after a power cut (to be tested) | Backups opt-in, encrypted per account, kept 7 days, deleted with the desktop |

## Agent Oyen first

Agent Oyen has a single owner today, so it needs exactly one desktop, sized Sedang.

- Its browser worker moves inside the desktop and talks to Chrome on 127.0.0.1:9222. Downloads and PDF capture stay local and keep working.
- The workarounds a headless browser needs go away, and sign-in popups can work.
- Quick anonymous reads keep using the headless worker it has today. The desktop is for sign-ins, sites that refuse headless browsers, and Take control.
- The desktop is a kiosk: no terminal or file manager, and Chrome policies that block DevTools, `file://` pages and extensions.
- Agent Oyen's own live panel stays the default. A new "Full desktop" mode relays noVNC through Agent Oyen's own server.

## Steps

**Demo 0** (2–3 engineer-days, after Kurnia's OK)
- One desktop container on Mac-studio, made by hand (2 vCPU, 3 GB): Xfce, Chrome with CDP on loopback, and noVNC.
- An SSH tunnel to its CDP port, and an Agent Oyen branch that connects over CDP. Luca watches in noVNC.
- No Swift and no merges. Nothing changes in the helper or `ms-w-ht96lu4`. The helper counts only its own VMs, so the demo's 3 GB sits outside its budget for those days. The container is removed afterwards.

Done when: the Agent Oyen branch drives Chrome in the desktop while Luca watches it live.

**Stage 0: checks on the machine** (5–7 engineer-days, 2–3 weeks on the calendar)
- Isolation: a desktop whose root flushes its own firewall still can't reach the LAN, other private networks, Mac-studio's services or another desktop.
- Bandwidth caps and a WireGuard exit work next to Apple's VM networking.
- The office's upload speed at peak hours, one desktop's memory over 72 hours, and Google and X sign-in with CDP attached.
- The Apple `container` version, chosen together, and an answer on the macOS licence question (section 2I).

Gates: Kurnia's terms in writing, the Mac-studio changes approved, and a UPS bought.

**Stage 1: Agent Oyen on its desktop** (about 30–45 engineer-days)
- The desktop kind on the macOS helper, the shared key layer in the parent, the port proxy, the CDP path, the minimal host firewall and own network, start after reboot, the kiosk template, and Agent Oyen's worker inside its desktop.

Done when:
- Agent Oyen runs for 4 weeks on Mac-studio;
- a desktop is usable within 20 seconds of waking, 95% of the time;
- Mac-studio never swaps at the measured maximum.

**Stage 2: invite-only developers** (about 40–55 engineer-days)
- Screen-action routes, bash and files, live links, bandwidth caps, a separate internet exit, a kill switch and a connection log, backups, outside uptime alerts, awake-hour metering, prepaid credit, rules of use, an MCP server and docs.

**Later:** SDKs, snapshots and templates, resize, public URLs, and a second or bigger Mac.

The day counts are estimates from reading the code, not measurements. Agents write code 2–4× faster than that. Approvals, Mac-only builds, image builds and on-site work don't speed up, and the Swift parts need a Mac to build and test on. Add 1.5–2.5 weeks per stage if merges happen weekly.

## Not in v1

Windows and macOS desktops, GPUs, snapshots and clones, resize, public URLs, sign-up and card billing.

## Questions for Kurnia

Each has a suggestion; any of them can change.

1. **May Mac-studio run Ruvio's desktop image and `desktopd` for paying developers, and on what terms?** Ruvio's code is in your private repo. Suggestion: written terms before any outside customer.
2. **Build on the macOS helper (H) rather than a second Ruvio install (A)?** A fights the helper for the same 36 GB. Suggestion: H.
3. **Add a shared key, team, limit and usage layer to the parent?** Desktops use it first, and the sandbox routes in #5 reuse it. Suggestion: yes, as small PRs, parent first.
4. **Approve the Mac-studio changes?** Pin the helper's RAM allowance, a separate desktop network, a root firewall runner, remove the ~86 GB of old Tart images, a newer Apple `container` chosen together, automatic restart, and the helper starting again by itself after a reboot. Suggestion: yes, in stage 0.
5. **Allow raw screen input and shell for developer computers?** Ruvio's API plan rules them out today. Suggestion: yes, only on developer computers, after the host firewall.

For Luca: the business side, which internet exit customer traffic uses, root for developers, the brand and domain, and legal advice before outside sign-up.

## Risks

- **Abuse from the office's address.** One spammer or scanner can get the office's internet address blocklisted, for the office and everything on its line. Keys stay with our own agents until customer traffic has its own exit.
- **One Mac, one line.** A power or internet cut takes every desktop with it. Automatic restart and a UPS come first.
- **Young tools.** Apple `container` gives a VM a new IP on every start, and its service doesn't come back by itself after a reboot.
- **Licences.** Whether Apple's macOS licence allows hosting Linux VMs for others is unclear (section 2I). Google Chrome's terms for hosted use are unchecked; Chromium is the fallback. Tart's licence has banned competing services since 5 June 2026, so this plan doesn't use Tart.
- **The memory numbers are estimates.** None of them is measured on Mac-studio yet.

## What changes where

- `contract/openapi.yaml`: a desktop capability and kind, and the helper's desktop routes (screen actions, commands, files, port proxy). Parent first.
- `agent/macos`: the desktop kind (it boots the desktop image and runs its fixed setup steps), the routes through `desktopd`, the port proxy for live view and CDP, the root firewall runner, and start after reboot.
- `agent/fake`: the desktop routes, for the conformance suite.
- `control-plane`: the key, team, limit and usage layer (shared with #5), the public `/v1/computers` routes, and live-link and CDP tokens.
- `frontend`: API keys, Desktops and Usage pages.
- Ruvio's repo: nothing changes. This repo holds only the desktop image's tag and the fixed setup steps.

## Sources

Read-only checks on 24 Oct 2026: Ruvio's repo (24351b5), this repo (51d3617), the sandbox plan (#5) and Agent Oyen's code. Nothing was changed on any machine.

- Orgo: [pricing](https://www.orgo.ai/pricing.md), [instance types](https://docs.orgo.ai/guides/instance-types), [embedding a desktop](https://docs.orgo.ai/guides/embed-vms), [API spec](https://docs.orgo.ai/api-reference/openapi.json)
- Apple: [`container` resource use](https://github.com/apple/container/blob/main/docs/resource-usage.md), [`container` releases](https://github.com/apple/container/releases), [macOS Tahoe licence](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf)
- [Tart's licence](https://raw.githubusercontent.com/cirruslabs/tart/main/LICENSE) · [Windows 11 on Apple silicon Macs](https://support.microsoft.com/en-us/windows/options-for-using-windows-11-with-mac-computers-with-apple-m1-m2-and-m3-chips-cd15fd62-9b34-4b78-b0bc-121baa3c568c)
