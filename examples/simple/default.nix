{ pkgs, cpp }:

let
  lib = pkgs.lib;
  root = ./.;
  sources = [
    "src/main.cc"
    "src/math.cc"
  ];
  includeDirs = [ "include" ];

  strict = cpp.mkExecutable {
    name = "simple-strict";
    inherit root sources includeDirs;
    depsManifest = ./deps.json;
  };

  scannedManifest = cpp.mkDependencyScanner {
    name = "simple-scanner";
    inherit root sources includeDirs;
  };

  scanned = cpp.mkExecutable {
    name = "simple-scanned";
    inherit root sources includeDirs;
    scanner = scannedManifest;
  };

  mkRunCheck = { drv, expectedLines, name }:
    let
      assertions = lib.concatStringsSep "\n"
        (map (line: "${pkgs.gnugrep}/bin/grep -F ${lib.escapeShellArg line} \"$tmp\" >/dev/null") expectedLines);
    in
    pkgs.runCommand name { } ''
      set -euo pipefail
      tmp=$TMP/result
      ${drv}/bin/${name} > "$tmp"
      ${assertions}
      mkdir -p "$out"
      cp "$tmp" "$out/output.txt"
    '';

  strictCheck = mkRunCheck {
    drv = strict;
    expectedLines = [ "2 + 3 = 5" "4 * 5 = 20" ];
    name = "simple-strict";
  };

  scannedCheck = mkRunCheck {
    drv = scanned;
    expectedLines = [ "2 + 3 = 5" "4 * 5 = 20" ];
    name = "simple-scanned";
  };

in
{
  packages = {
    inherit strict scanned;
  };

  checks = {
    simpleStrict = strictCheck;
    simpleScanned = scannedCheck;
  };

  inherit scannedManifest;
}
