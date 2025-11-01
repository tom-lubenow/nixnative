{ pkgs, packages }:

let
  strict = packages.strict;
  scanned = packages.scanned;

  mkRunCheck = { drv, expectedLines, name }:
    let
      assertions = pkgs.lib.concatStringsSep "\n"
        (map (line: "${pkgs.gnugrep}/bin/grep -F ${pkgs.lib.escapeShellArg line} \"$tmp\" >/dev/null") expectedLines);
    in
    pkgs.runCommand name { } ''
      set -euo pipefail
      tmp=$TMP/result
      ${drv}/bin/${name} > "$tmp"
      ${assertions}
      mkdir -p "$out"
      cp "$tmp" "$out/output.txt"
    '';

in {
  simpleStrict = mkRunCheck {
    drv = strict;
    expectedLines = [
      "2 + 3 = 5"
      "4 * 5 = 20"
      "build summary: nixclang-simple v1.0.0 (mode=strict)"
      "zlib version: "
    ];
    name = "simple-strict";
  };

  simpleScanned = mkRunCheck {
    drv = scanned;
    expectedLines = [
      "2 + 3 = 5"
      "4 * 5 = 20"
      "build summary: nixclang-simple v1.0.0 (mode=scanner)"
      "zlib version: "
    ];
    name = "simple-scanned";
  };

  simpleScanManifest = pkgs.writeText "simple-scanner.json"
    (builtins.toJSON packages.scanned.passthru.manifest);
}
