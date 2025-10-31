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
            examples = import ./examples/examples.nix { inherit pkgs cpp; };
          in
          f { inherit pkgs cpp examples; }
        );
    in
    {
      lib = {
        cpp = import ./nix/cpp;
      };

      packages = forAllSystems ({ examples, ... }:
        examples.packages // {
          default = examples.defaults.app;
        }
      );

      checks = forAllSystems ({ examples, ... }:
        examples.checks // {
          simpleScanManifest = examples.manifests.appWithLibrary;
        }
      );

      apps = forAllSystems ({ pkgs, examples, ... }:
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
  nix run .#cpp-sync-manifest -- .#checks.x86_64-linux.simpleScanManifest examples/app-with-library/deps.json
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

      devShells = forAllSystems ({ pkgs, cpp, ... }:
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
