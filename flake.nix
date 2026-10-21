{
  description = "MetaService: Root, Agents and chat bundle for managing machines and their VMs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        # Python for the contract conformance tests and the Fake Agent (test tools only).
        python = pkgs.python3.withPackages (ps: [ ps.jsonschema ps.pyyaml ]);
        # The Rust Agent built with the given cross package set (musl, linked statically).
        staticLinuxAgent = cross: cross.rustPlatform.buildRustPackage {
          pname = "metaservice-agent";
          version = "0.1.0";
          src = ./agent/linux;
          cargoLock.lockFile = ./agent/linux/Cargo.lock;
          doCheck = false;
          env.RUSTFLAGS = "-C target-feature=+crt-static";
        };
      in {
        # `nix build .#metaservice-agent-linux` builds the Rust Agent for the machine it runs on (do this on the Linux machine).
        packages.metaservice-agent-linux = pkgs.rustPlatform.buildRustPackage {
          pname = "metaservice-agent";
          version = "0.1.0";
          src = ./agent/linux;
          cargoLock.lockFile = ./agent/linux/Cargo.lock;
          doCheck = false;
        };

        # `nix build .#metaservice-agent-linux-x86_64` and `.#metaservice-agent-linux-arm64` cross-build the Rust Agent for a Linux PC
        # (x86_64) or a Linux ARM computer such as the DGX Spark (aarch64), static musl, from any machine, a Mac included.
        # The parent finds them in its builds folder as metaservice-agent-linux-x86_64 / -linux-arm64 (see docs/RUNNING.md;
        # scripts/build-linux-helpers.sh builds both and puts them there).
        # Rust links them statically itself (crt-static), so they run on any Linux computer with no nix store and no libraries.
        packages.metaservice-agent-linux-x86_64 = staticLinuxAgent pkgs.pkgsCross.musl64;
        packages.metaservice-agent-linux-arm64 = staticLinuxAgent pkgs.pkgsCross.aarch64-multiplatform-musl;

        # `nix develop` gives every build tool, pinned by flake.lock. Swift is not here:
        # on macOS it stays the system toolchain (Xcode Command Line Tools).
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Linux Agent (Rust)
            rustc
            cargo
            clippy
            rustfmt
            cargo-audit
            # panel UI (Svelte + Vite)
            nodejs
            # data, scan, tooling
            sqlite
            nmap
            openssl
            jq
            curl
            git
            python
          ];
          shellHook = ''
            echo "MetaService devShell ready (rust, node, sqlite, nmap, openssl, jq, python via Nix)."
            echo "Not via Nix: Swift uses the system toolchain on macOS."
          '';
        };
      });
}
