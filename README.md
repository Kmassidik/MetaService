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

4. To create VMs on a Mac, the machine needs Apple's `container` tool (github.com/apple/container). The form tells you if it is missing.
   Install it, then stop and start the parent again with `./install.sh`.

To stop the parent: `pkill -f metaservice-root`.

## What works today

- The parent with its panel: Overview, Machines, per-machine Deployments, Token ledger, Health and Settings.
- The macOS and Linux Agents, and the Ruvio chat on a machine or VM.
- Not yet: adding another computer over SSH, installing Apple's `container` tool for you, and the chat's files, connected apps and routines.

## Test

```sh
scripts/test-all.sh      # every test, on your working folder
scripts/clean-room.sh    # the same, on a fresh copy of the last commit
```

Both need Nix, Xcode's Swift and Google Chrome.
