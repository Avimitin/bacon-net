{
  description = "bacon-net — e-amusement server rewritten in Elixir";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        beam = pkgs.beam27Packages.overrideScope (final: prev: {
          elixir = prev.elixir_1_18;
        });
        elixir = beam.elixir;
        erlang = beam.erlang;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            elixir
            erlang
            git
            nodejs_22
          ];

          shellHook = ''
            export MIX_HOME="$PWD/.nix-mix"
            export HEX_HOME="$PWD/.nix-hex"
            export PATH="$MIX_HOME/escripts:$MIX_HOME/bin:$PATH"
            export ERL_AFLAGS="-kernel shell_history enabled"
            mix local.hex --force >/dev/null 2>&1 || true
            mix local.rebar --force >/dev/null 2>&1 || true
          '';
        };

        packages.frontend = pkgs.buildNpmPackage {
          pname = "bacon-net-webui";
          version = "0.1.0";
          src = ./frontend;

          npmDepsHash = "sha256-uRq6SvQuCwxt9LdZ8wmphEWIG5Ty5YM+AisxQvLgok0=";

          installPhase = ''
            runHook preInstall
            cp -r dist $out
            runHook postInstall
          '';
        };

        packages.default = beam.mixRelease {
          pname = "bacon-net";
          version = "0.1.0";
          src = ./.;

          # keep releases/COOKIE so the server starts without extra env vars
          removeCookie = false;

          # bundle the built webui so the release serves it under /webui
          preBuild = ''
            mkdir -p priv/static
            cp -r ${self.packages.${system}.frontend}/* priv/static/
          '';

          mixFodDeps = beam.fetchMixDeps {
            pname = "bacon-net-deps";
            version = "0.1.0";
            src = ./.;
            hash = "sha256-pb3Oz5ViTc9za6Fg45yEaH3N9eM3NzP5DdVLj/W/k7w=";
          };
        };
      });
}
