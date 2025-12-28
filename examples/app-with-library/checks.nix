{ pkgs, packages }:

let
  app = packages.app;

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
  simpleApp = mkRunCheck {
    drv = app;
    expectedLines = [
      "2 + 3 = 5"
      "4 * 5 = 20"
      "build summary: nixnative-simple v1.0.0 (mode=dynamic)"
      "zlib version: "
    ];
    name = "simple-app";
  };
}
