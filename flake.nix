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
      in {
        # `nix build .#metaservice-agent-linux` builds the Rust Agent for the machine it runs on (do this on the Linux machine).
        packages.metaservice-agent-linux = pkgs.rustPlatform.buildRustPackage {
          pname = "metaservice-agent";
          version = "0.1.0";
          src = ./agent/linux;
          cargoLock.lockFile = ./agent/linux/Cargo.lock;
          doCheck = false;
        };

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
