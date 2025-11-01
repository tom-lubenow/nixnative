{ pkgs, packages }:

let
  exe = packages.rustInteropExample;
in {
  rustInterop = pkgs.runCommand "rust-integration-check" { } ''
    set -euo pipefail
    output=$(${exe}/bin/rust-integration)
    echo "$output" | ${pkgs.gnugrep}/bin/grep -F "rust_add(21, 21) = 42" >/dev/null
    echo "$output" | ${pkgs.gnugrep}/bin/grep -F "rust_scale(7, 3) = 21" >/dev/null
    mkdir -p "$out"
    printf '%s\n' "$output" > "$out/output.txt"
  '';
}
