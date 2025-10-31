{ pkgs, cpp }:

let
  lib = pkgs.lib;
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/main.cc" "src/hello.cc" ];

  executable = cpp.mkExecutable {
    name = "executable-example";
    inherit root sources includeDirs;
    depsManifest = ./deps.json;
  };

  runCheck = pkgs.runCommand "executable-example-check" { } ''
    set -euo pipefail
    output=$(${executable}/bin/executable-example)
    test "$output" = "Hello from nixclang executable example"
    mkdir -p "$out"
    echo "$output" > "$out/result.txt"
  '';

in {
  packages = {
    executableExample = executable;
  };

  checks = {
    executableExample = runCheck;
  };
}
