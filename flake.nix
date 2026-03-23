{
  description = "Claude Code jailed with bubblewrap via jail.nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";

    # Claude Code from the community flake (provides overlay with pkgs.claude-code)
    claude-code.url = "github:sadjow/claude-code-nix";

    # Alternatively, use claude-code from nixpkgs you can drop the input above
    # and remove the overlay below — just use pkgs.claude-code directly.
  };

  outputs =
    {
      flake-parts,
      nixpkgs,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { system, ... }:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              inputs.claude-code.overlays.default

              # If using claude-code from nixpkgs instead, remove this overlay
              # and the claude-code input entirely.
            ];
          };

          jail = inputs.jail-nix.lib.extend {
            inherit pkgs;
          };

          # ── Extra packages to make available inside the jail ──
          # Add any packages Claude Code needs for your project here.
          extraPackages = with pkgs; [
            # e.g. nodejs_24, pnpm, go, python3, postgresql
          ];

          claude-jailed = jail "claude-jail" pkgs.claude-code (
            with jail.combinators;
            let
              certpath = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            in
            [
              # ── Core sandbox setup ──
              mount-cwd # mount the current working directory read-write
              network # allow network access
              no-new-session # share the host session (needed for terminal control)
              time-zone # inherit host timezone
              (ro-bind "${pkgs.coreutils}/bin/env" "/usr/bin/env")

              # ── Base tools Claude Code expects ──
              (add-pkg-deps (
                with pkgs;
                [
                  bashInteractive
                  coreutils
                  curl
                  diffutils
                  fd
                  findutils
                  gawk
                  git
                  gnugrep
                  gnused
                  gnutar
                  gzip
                  jq
                  less
                  nix
                  ps
                  python3
                  ripgrep
                  tree
                  unzip
                  wget
                  which
                ]
              ))

              # ── Your extra project packages ──
              (add-pkg-deps extraPackages)

              # ── Claude Code flags ──
              (set-argv [
                "--dangerously-skip-permissions"
                (noescape "\"$@\"")
              ])

              # ── Claude config (read-write so it can update state) ──
              (try-readwrite (noescape "~/.claude"))
              (try-readwrite (noescape "~/.claude.json"))

              # ── TLS certificates ──
              # Fixes UNABLE_TO_GET_ISSUER_CERT_LOCALLY errors
              # See: https://github.com/anthropics/claude-code/issues/2816
              (readonly certpath)
              (set-env "NODE_EXTRA_CA_CERTS" certpath)

              # ── Pass through folders (examples) ──
              # Read-only access to a config directory:
              # (try-readonly (noescape "~/.config/some-tool"))
              #
              # Read-write access to a data directory:
              # (try-readwrite (noescape "~/.local/share/my-app"))

              # ── Pass through environment variables (examples) ──
              # Forward an env var from the host (only if set):
              # (try-fwd-env "CAKE_WITH_FILE")
            ]
          );
        in
        {
          # `nix develop` gives you a shell with the jailed claude available
          devShells.default = pkgs.mkShell {
            packages = [
              claude-jailed
            ];
          };

          # `nix build` produces the jailed wrapper script
          packages.default = claude-jailed;
        };
    };
}
