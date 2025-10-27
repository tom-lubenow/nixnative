{
  description = "Incremental clang build graph using Nix per translation unit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          let
            pkgs = import nixpkgs {
              inherit system;
            };
            cpp = import ./nix/cpp { inherit pkgs; };
            example = import ./examples/simple { inherit pkgs cpp; };
          in
          f { inherit pkgs cpp example; }
        );
    in
    {
      lib = {
        cpp = import ./nix/cpp;
      };

      packages = forAllSystems ({ pkgs, cpp, example }:
        example.packages // {
          default = example.packages.strict;
        }
      );

      checks = forAllSystems ({ pkgs, cpp, example }:
        example.checks // {
          simpleScanManifest = example.scannedManifest;
        }
      );

      apps = forAllSystems ({ pkgs, cpp, example }:
        let
          syncManifest = pkgs.writeShellApplication {
            name = "sync-manifest";
            runtimeInputs = [ pkgs.nix pkgs.jq pkgs.coreutils ];
            text = ''
              set -euo pipefail

              usage() {
                cat <<'USAGE'
Usage: sync-manifest <flake-attr> <destination> [nix build args...]

Example:
  nix run .#cpp-sync-manifest -- .#checks.x86_64-linux.simpleScanManifest examples/simple/deps.json
USAGE
              }

              if [ "$#" -lt 2 ]; then
                usage >&2
                exit 1
              fi

              attr="$1"
              dest="$2"
              shift 2

              out_path=$(nix build "$attr" --no-link --print-out-paths "$@")
              tmp=$(mktemp)
              cp "$out_path" "$tmp"
              mkdir -p "$(dirname "$dest")"
              jq '.' "$tmp" > "$dest.tmp"
              mv "$dest.tmp" "$dest"
              echo "updated $dest from $attr" >&2
            '';
          };
        in
        {
          cpp-sync-manifest = {
            type = "app";
            program = "${syncManifest}/bin/sync-manifest";
            meta.description = "Copy a dependency manifest derivation to a workspace file";
          };
        }
      );

      devShells = forAllSystems ({ pkgs, cpp, example }:
        {
          default = pkgs.mkShell {
            packages = [
              cpp.toolchains.clang.clang
              pkgs.llvmPackages_18.lld
              pkgs.nix
              pkgs.git
            ];
            shellHook = ''
              echo "nixclang dev shell loaded"
            '';
          };
        }
      );
    };
}
