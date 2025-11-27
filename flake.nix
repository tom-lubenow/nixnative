{
  description = "Incremental clang build graph using Nix per translation unit";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.crane.url = "github:ipetkov/crane/v0.16.1";
  inputs.crane.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, crane }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          let
            pkgs = import nixpkgs { inherit system; };
            cpp = import ./nix/cpp { inherit pkgs; };
            craneLib = crane.lib.${system};
            examples = import ./examples/examples.nix {
              inherit pkgs cpp system;
              inherit craneLib;
            };
          in
          f { inherit pkgs cpp examples; }
        );
    in
    {
      lib = {
        cpp = import ./nix/cpp;
        native = import ./nix/native;
      };

      packages = forAllSystems ({ examples, ... }:
        examples.packages // {
          default = examples.defaults.app;
        }
      );

      checks = forAllSystems ({ pkgs, cpp, examples, ... }:
        examples.checks // {
          pkgconfig-zlib = pkgs.runCommand "pkgconfig-zlib-check" { } ''
            set -euo pipefail
            drv=${(cpp.pkgConfig.makeLibrary {
              name = "zlib";
              packages = [ pkgs.zlib ];
              modules = [ "zlib" ];
            }).drv}
            grep -q -- "-lz" "$drv"
            test "$(grep -c 'includeDirs' "$drv")" -gt 0
            touch "$out"
          '';
        }
      );

      apps = forAllSystems ({ pkgs, examples, ... }:
        let
          syncManifest = pkgs.writeShellApplication {
            name = "sync-manifest";
            runtimeInputs = [ pkgs.nix pkgs.coreutils ];
            text = ''
              set -euo pipefail

              usage() {
                cat <<'USAGE'
Usage: sync-manifest <flake-attr> <destination> [nix build args...]

Example:
  nix run .#cpp-sync-manifest -- .#checks.x86_64-linux.simpleScanManifest examples/app-with-library/.clang-deps.nix
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
              tmp_json=$(mktemp)
              cp "$out_path" "$tmp_json"
              tmp_nix="$dest.tmp"
              mkdir -p "$(dirname "$dest")"
              ${pkgs.python3}/bin/python - "$tmp_json" "$tmp_nix" <<'PY'
import json
import re
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

with json_path.open('r', encoding='utf-8') as fh:
    data = json.load(fh)

ident = re.compile(r'^[A-Za-z_][A-Za-z0-9_-]*$')

def format_key(key: str) -> str:
    return key if ident.match(key) else json.dumps(key)

def emit(node, indent=0):
    pad = '  ' * indent
    if isinstance(node, dict):
        lines = [pad + '{']
        for key in sorted(node):
            child = emit(node[key], indent + 1)
            key_str = format_key(key)
            if len(child) == 1:
                lines.append(f"{pad}  {key_str} = {child[0].lstrip()};")
            else:
                first, *rest = child
                lines.append(f"{pad}  {key_str} = {first.lstrip()}")
                if rest:
                    lines.extend(rest[:-1])
                    lines.append(rest[-1] + ';')
                else:
                    lines[-1] += ';'
        lines.append(pad + '}')
        return lines
    if isinstance(node, list):
        lines = [pad + '[']
        for item in node:
            lines.extend(emit(item, indent + 1))
        lines.append(pad + ']')
        return lines
    if isinstance(node, str):
        return [pad + json.dumps(node)]
    if isinstance(node, bool):
        return [pad + ('true' if node else 'false')]
    if node is None:
        return [pad + 'null']
    return [pad + str(node)]

lines = emit(data)
out_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
              mv "$tmp_nix" "$dest"
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

      devShells = forAllSystems ({ pkgs, cpp, examples }:
        {
          default = cpp.mkDevShell {
            target = examples.defaults.app;
            extraPackages = [ pkgs.nix pkgs.git ];
          };
        }
      );
    };
}
