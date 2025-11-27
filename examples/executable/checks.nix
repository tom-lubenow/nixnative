{ pkgs, packages }:

let
  exe = packages.executableExample;

in {
  executableExample = pkgs.runCommand "executable-example-check" { } ''
    set -euo pipefail
    output=$(${exe}/bin/executable-example)
    test "$output" = "Hello from nixnative executable example"
    mkdir -p "$out"
    echo "$output" > "$out/result.txt"
  '';
}
