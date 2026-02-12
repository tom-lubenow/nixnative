#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "incrementality-gate: ripgrep (rg) is required" >&2
  exit 2
fi

system="${1:-$(nix eval --impure --raw --expr builtins.currentSystem)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

nonce="$(date +%s%N)"

cat > "$tmp_dir/flake.nix" <<FLAKE
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.nixnative.url = "path:${repo_root}";

  outputs = { nixpkgs, nixnative, ... }:
    let
      system = "${system}";
      pkgs = import nixpkgs { inherit system; };
      nixPackage = nixnative.inputs.nix.packages."${system}".default;
      ninjaPackages = nixnative.inputs.nix-ninja.packages."${system}";
      native = nixnative.lib.native {
        inherit pkgs nixPackage;
        inherit (ninjaPackages) nix-ninja nix-ninja-task;
      };
      proj = native.project {
        root = ./.;
        compileFlags = [ "-O2" ];
      };
      app = proj.executable {
        name = "incrementality-app";
        sources = [ "a.cc" "b.cc" ];
      };
    in
    {
      legacyPackages."${system}".default = native.realizeTarget app;
    };
}
FLAKE

cat > "$tmp_dir/a.cc" <<EOF_SRC
int from_a() { return 40; }
// nonce ${nonce}
EOF_SRC

cat > "$tmp_dir/b.cc" <<'EOF_SRC'
#include <iostream>
int from_a();

int main() {
  std::cout << (from_a() + 2) << std::endl;
  return 0;
}
EOF_SRC

build_target() {
  local log_file="$1"
  (
    cd "$tmp_dir"
    nix build ".#legacyPackages.${system}.default" --no-link -L >"$log_file" 2>&1
  )
}

compile_count() {
  local log_file="$1"
  grep -c "nix-ninja-task: Compiling" "$log_file" || true
}

extract_object_drv() {
  local log_file="$1"
  local source_stem="$2"
  rg -o "building '/nix/store/[^']*-ninja-build-${source_stem}-[a-z0-9]+\\.o\\.drv'" "$log_file" \
    | sed -E "s/^building '([^']+)'$/\\1/" \
    | tail -n 1
}

log1="$tmp_dir/build-1.log"
log2="$tmp_dir/build-2.log"
log3="$tmp_dir/build-3.log"

build_target "$log1"
build_target "$log2"

cat > "$tmp_dir/a.cc" <<EOF_SRC
int from_a() { return 41; }
// nonce ${nonce} edited
EOF_SRC

build_target "$log3"

count1="$(compile_count "$log1")"
count2="$(compile_count "$log2")"
count3="$(compile_count "$log3")"

b_drv_first="$(extract_object_drv "$log1" "b-cc")"
b_drv_third="$(extract_object_drv "$log3" "b-cc")"

echo "incrementality-gate: compile counts first=${count1} second=${count2} third=${count3}"
echo "incrementality-gate: b.cc object drv first=${b_drv_first} third=${b_drv_third}"

if [ "${count1}" -lt 2 ]; then
  echo "incrementality-gate: expected first build to compile at least 2 sources" >&2
  exit 1
fi

if [ "${count2}" -ne 0 ]; then
  echo "incrementality-gate: expected second build (no changes) to compile 0 sources" >&2
  exit 1
fi

if [ "${count3}" -ne 1 ]; then
  echo "incrementality-gate: expected exactly 1 compile after editing one source; got ${count3}" >&2
  exit 1
fi

if [ -z "${b_drv_first}" ] || [ -z "${b_drv_third}" ]; then
  echo "incrementality-gate: failed to extract b.cc object derivation paths" >&2
  exit 1
fi

if [ "${b_drv_first}" != "${b_drv_third}" ]; then
  echo "incrementality-gate: unchanged b.cc should keep same object derivation path" >&2
  exit 1
fi

echo "incrementality-gate: PASS"
