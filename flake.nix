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
