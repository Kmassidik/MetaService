# MetaService

One control panel (the **parent**) that manages VMs on many machines. Each machine runs a small **Agent** that creates, starts, stops and deletes its VMs.
A machine can also run **Ruvio**, a chat, and the parent gives the chat its AI, so no machine holds an AI key.

parent → machines → VMs

## Install

You need an Apple Silicon Mac with Swift (from Xcode or its command-line tools) and Python 3. The parent only runs on that kind of Mac for now.

1. Get the code and start the parent:

   ```sh
   git clone https://github.com/Kmassidik/MetaService.git
   cd MetaService
   ./install.sh
   ```

   A welcome opens with three choices: **1 Help**, **2 README**, **3 Install**. Choose **3**. It checks your settings and your computer, then builds and starts MetaService.
   The first start builds everything, so allow a few minutes. Leave it running.
   Prefer one command? `./install.sh install` skips the welcome, and `./install.sh --check` only checks.

2. Open http://localhost:9100 on the same Mac. The first visit asks you to create the admin login.
   It also asks for the setup token. Find it in `control-plane/arm64/.env`, on the line `ROOT_SETUP_TOKEN=`. The parent writes it there on its first start.

3. Press **Add machine**. The form checks the computer, then installs MetaService on it. Today that means the same Mac the parent runs on.

4. To create VMs, a Mac needs Apple's `container` tool. If it is missing, the install adds it: it downloads Apple's signed package from github.com/apple/container (about 118 MB),
   checks that it is the file we expect and that Apple signed it, then installs it. Your Mac asks for your password once, in the terminal. Then it starts Apple's container service.
   To go without VMs, run `./install.sh install --skip-container`.

   The install also checks for nmap, which "Find machines" uses to sweep the network. If it is missing, the install adds only nmap with Homebrew (no password, and no `brew update`, so nothing else changes). nmap is optional: if Homebrew is not there or fails, the install says so and goes on, and `--skip-nmap` goes without it.

Stop it from the menu (choice 6) or with `./install.sh stop`. You sign in to the panel in your browser (the admin login from step 2); there is no sign-in in the terminal.

## Start again after a reboot

By default the parent is a plain background process and the Cloudflare connector is a user job, so after a reboot with nobody logged in neither comes back. To fix that:

```sh
./install.sh autostart on      # needs sudo once (see below)
./install.sh autostart status  # installed / loaded / running, and whether the panel answers
./install.sh autostart off     # remove both; MetaService is then stopped
```

`autostart on` installs two system LaunchDaemons that run as you (not root), so they start at boot without a login: `io.metaservice.parent` (the built parent, restarted if it stops) and, when remote access is set up and `cloudflared` is installed, `io.metaservice.connector`.
It stops the parent you started by hand and the user connector job, loads the daemons, and waits for http://127.0.0.1:9100. Run `./install.sh install` first: it refuses until the parent is built.
It never asks for a password. It uses `sudo -n`; if that does not work it prints the exact commands to run yourself (or run `sudo -v` and try again). With autostart on, `./install.sh stop` does not stop it (launchd would restart it): use `autostart off`.

## Uninstall

Choose **7 Uninstall** in the menu, or run `./install.sh uninstall`. It stops MetaService and shows what it will remove, with sizes: the builds, the packages, the run files and your data (machines, admin login, keys). It asks you to type `yes` first.
It keeps the source code, git, Apple's `container` tool and, unless you say so, your `.env`. `./install.sh uninstall --keep-data` keeps your data too, and `--env` also removes `.env`.

## Reach the panel from outside

The panel normally answers only on the Mac it runs on. To open it from anywhere, MetaService can make its own Cloudflare Tunnel, with a name such as `meta.example.com`. The tunnel and its connector belong to MetaService alone: another project's tunnel is never read or changed. The panel's own admin login is the gate, so use a long password (12 characters or more is required once it is public).

1. In `control-plane/arm64/.env` set `PUBLIC_BASE_URL` (an https name with no port or path), and `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_ZONE_ID`. The token needs Zone DNS: Edit and Account Cloudflare Tunnel: Edit. Do not set `CLOUDFLARE_TUNNEL_ID`.
2. Start MetaService, then run `./install.sh remote plan`. It changes nothing and says what is ready and what is missing.
3. Try a throwaway name first: `./install.sh remote up --host meta-test.example.com --tunnel-name metaservice-test`, check it, then `./install.sh remote down`.
4. Run `./install.sh remote up`. It makes the tunnel, one route to the panel, one proxied DNS record, an owner-only token file and a launchd job for the connector, and says when the name answers.
5. `./install.sh remote status` shows whether it is connected. `./install.sh remote down` removes exactly what `up` made. Uninstall does this first.

Once `PUBLIC_BASE_URL` is set the panel answers only under that name. The API token is read from `.env` only and is never printed.

## What works today

- The parent with its panel: Overview, Machines, per-machine Deployments, Token ledger, Health and Settings.
- The macOS and Linux Agents, and the Ruvio chat on a machine or VM.
- Adding another computer on the same network from the panel: Connect over SSH (password once, or the parent's key), read-only Verify, "What will change", then Install into an isolated folder (`~/metaservice-box`). The parent keeps an SSH tunnel to it, shows connected or offline, and removal puts the computer back exactly as it was. Tested on this laptop only.
- Built but not switched on: the own-user install on Linux (needs sudo) and the WireGuard transport. Both are unit-tested and unverified on real hardware.
- Not yet: the chat's files, connected apps and routines.
- CPU settings in Create VM, as in Proxmox's Processors window: sockets, a CPU type and CPU flags for a VM on a Linux machine, and a CPU limit for a container. A Mac gives a VM its own CPU. A Linux machine offers them only when it can make VMs (see below).

## A Linux machine that makes VMs

A Linux machine makes VMs with Incus, and only when its CPU's virtualization is switched on. Containers do not need it, so a machine without it still runs containers and the panel calls it "containers only".

1. In the computer's BIOS, switch on **SVM Mode** (AMD) or **Intel Virtualization Technology** (VT-x, Intel). Only the BIOS can do this; Linux cannot turn it on later.
2. After the restart, start the helper again. An install in a folder does not start by itself after a restart: run `~/metaservice-box/start.sh`.
3. Check that the machine can make VMs:
   - `ls /dev/kvm` lists a device.
   - `dmesg | grep -i kvm` does not say "disabled by bios".
   - `incus info | grep -A1 driver` says `lxc | qemu`. Without `qemu`, install QEMU and OVMF for Incus (on Ubuntu: `sudo apt install qemu-system-x86 ovmf`), then restart Incus with `sudo systemctl restart incus`.
4. In the panel, press **Update helper** on that machine, so it runs a helper that offers the CPU settings.

Create VM then offers, on that machine:
- the CPU types its QEMU knows (Type, with the Vendor beside each);
- `nested-virt` and `aes` (Extra CPU flags);
- more than one socket, on Incus 7.1 or 7.0.1 LTS and later.

## Test

```sh
scripts/test-all.sh      # every test, on your working folder
scripts/clean-room.sh    # the same, on a fresh copy of the last commit
```

Both need Nix, Xcode's Swift and Google Chrome.
