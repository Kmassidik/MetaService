# Building the Windows helper

The Windows helper lives in `agent/windows`. It cross-compiles from any machine with the
mingw-w64 toolchain. **First real build: 2026-11-18, on Kurnia's fedora laptop** (mingw64-gcc
dnf package + rustup stable with the x86_64-pc-windows-gnu std target), reached over the mesh
from the Mini. The produced exe is in the parent's build store and the hub lists
`windows x86_64: untested` — joinable.

## One-time toolchain

```sh
rustup target add x86_64-pc-windows-gnu aarch64-pc-windows-gnu
brew install mingw-w64        # macOS; provides the dlltool the gnu targets need
```

## Build (both architectures)

```sh
cd agent/windows
cargo build --release --target x86_64-pc-windows-gnu
cargo build --release --target aarch64-pc-windows-gnu
```

The outputs are `target/<target>/release/metaservice-agent.exe`. Name them for the parent's
build store and ship with checksums, same as the Linux helpers:

```sh
cp target/x86_64-pc-windows-gnu/release/metaservice-agent.exe  metaservice-agent-windows-x86_64.exe
cp target/aarch64-pc-windows-gnu/release/metaservice-agent.exe metaservice-agent-windows-arm64.exe
sha256sum metaservice-agent-windows-* > SHA256SUMS
# then scp to the Mini: ~/MetaService/control-plane/arm64/state/agent-builds/
```

The hub serves the `.exe` and the tunnel config (`<name>.conf`) from that folder; the join
script downloads both (see `join-share/script/join.ps1`).

## The aarch64 build (done once, 2026-11-18, on the DGX)

`aarch64-pc-windows-gnu` std is only distributed for x86_64 hosts, so the aarch64 build used the
`aarch64-pc-windows-gnullvm` target + llvm-mingw (standalone tarball from
github.com/mstorsjo/llvm-mingw/releases, ubuntu-22.04-aarch64 variant):

```sh
rustup target add aarch64-pc-windows-gnullvm
# extract llvm-mingw to ~/llvm, then:
CARGO_TARGET_AARCH64_PC_WINDOWS_GNULLVM_LINKER=~/llvm/bin/aarch64-w64-mingw32-gcc \
  cargo build --release --target aarch64-pc-windows-gnullvm
```
The DGX was used once and cleaned afterwards (rustup + llvm + crate all removed).

## What the build machine must be

Anything with the mingw toolchain. The crate itself has no Windows-only dependencies in v1
(axum, tokio, sysinfo, ureq are all cross-platform); the ConPTY terminal behind `/v1/host-terminal`
is cfg-gated: on a non-Windows build host it compiles as an honest 500 "needs a Windows build"
refusal, and the real ConPTY shell lands when someone builds on Windows or adds the `windows`
crate — see `agent/windows/src/conpty.rs`.

## Honest status

Until a real Windows machine joins once: **every Windows claim is "tested with fakes only, not
proven."** The hub marks windows builds `untested` (not `ready`) on purpose; the first real join
promotes it. See `docs/PRD-windows-helper.md` section 6.
