{ pkgs, packages }:

let
  exe = packages.rustCraneInterop;
in {
  rustCraneInterop = pkgs.runCommand "rust-crane-integration-check" { } ''
    set -euo pipefail
    output=$(${exe}/bin/rust-crane-integration)
    echo "$output" | ${pkgs.gnugrep}/bin/grep -F "rust_crane_dot(2, 5) = 10" >/dev/null
    echo "$output" | ${pkgs.gnugrep}/bin/grep -F "rust_crane_norm(3, 4) = 5" >/dev/null
    mkdir -p "$out"
    printf '%s\n' "$output" > "$out/output.txt"
  '';
}
