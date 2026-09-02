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
        elixir = pkgs.elixir_1_18;
        erlang = pkgs.erlang_27;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            elixir
            erlang
            git
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

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "bacon-net";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ elixir erlang pkgs.git ];

          HOME = ".";
          MIX_ENV = "prod";

          buildPhase = ''
            runHook preBuild
            export MIX_HOME="$PWD/.mix"
            export HEX_HOME="$PWD/.hex"
            mix local.hex --force
            mix local.rebar --force
            mix deps.get
            mix compile
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r . $out/
            runHook postInstall
          '';
        };
      });
}
