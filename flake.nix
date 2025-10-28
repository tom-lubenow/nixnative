{
  description = "Incremental clang build graph using Nix per translation unit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          let
            pkgs = import nixpkgs {
              inherit system;
            };
            cpp = import ./nix/cpp { inherit pkgs; };
            simple = import ./examples/simple { inherit pkgs cpp; };
            pythonExtension = import ./examples/python-extension { inherit pkgs cpp; };
          in
          f { inherit pkgs cpp simple pythonExtension; }
        );
    in
    {
      lib = {
        cpp = import ./nix/cpp;
      };

      packages = forAllSystems ({ pkgs, cpp, simple, pythonExtension }:
        simple.packages // pythonExtension.packages // {
          default = simple.packages.strict;
        }
      );

      checks = forAllSystems ({ pkgs, cpp, simple, pythonExtension }:
        simple.checks
        // pythonExtension.checks
        // {
          simpleScanManifest = simple.scannedManifest;
        }
      );

      apps = forAllSystems ({ pkgs, cpp, simple, pythonExtension }:
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

      devShells = forAllSystems ({ pkgs, cpp, simple, pythonExtension }:
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
