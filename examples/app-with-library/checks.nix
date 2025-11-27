{ pkgs, packages }:

let
  strict = packages.strict;
  scanned = packages.scanned;
  mathLib = packages.mathLib;

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

  mergeManifests = a: b:
    let
      aUnits = a.units or { };
      bUnits = b.units or { };
      keys = pkgs.lib.unique ((builtins.attrNames aUnits) ++ (builtins.attrNames bUnits));
      mergeEntry = name:
        let
          aEntry = aUnits.${name} or { };
          bEntry = bUnits.${name} or { };
          deps =
            pkgs.lib.unique (
              (aEntry.dependencies or [ ])
              ++ (bEntry.dependencies or [ ])
            );
        in
        {
          dependencies = deps;
        };
    in
    {
      schema = a.schema or b.schema or 1;
      units = builtins.listToAttrs (map (name: { inherit name; value = mergeEntry name; }) keys);
    };

  combinedManifest =
    mergeManifests mathLib.passthru.manifest scanned.passthru.manifest;

in {
  simpleStrict = mkRunCheck {
    drv = strict;
    expectedLines = [
      "2 + 3 = 5"
      "4 * 5 = 20"
      "build summary: nixnative-simple v1.0.0 (mode=strict)"
      "zlib version: "
    ];
    name = "simple-strict";
  };

  simpleScanned = mkRunCheck {
    drv = scanned;
    expectedLines = [
      "2 + 3 = 5"
      "4 * 5 = 20"
      "build summary: nixnative-simple v1.0.0 (mode=scanner)"
      "zlib version: "
    ];
    name = "simple-scanned";
  };

  simpleScanManifest = pkgs.writeText "simple-scanner.json"
    (builtins.toJSON combinedManifest);
}
