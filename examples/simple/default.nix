{ pkgs, cpp }:

let
  lib = pkgs.lib;
  root = ./.;
  sources = [
    "src/main.cc"
    "src/math.cc"
  ];
  includeDirs = [ "include" ];

  mkBuildInfoGenerator =
    mode:
    cpp.generators.jinja {
      name = "build-info-${mode}";
      inherit root;
      globalContext = {
        projectName = "nixclang-simple";
        version = {
          major = 1;
          minor = 0;
          patch = 0;
        };
      };
      templates = [
        {
          template = "templates/build_info.hpp.j2";
          output = "generated/build_info.hpp";
          context = { inherit mode; };
        }
        {
          template = "templates/build_info.cc.j2";
          output = "generated/build_info.cc";
          context = { inherit mode; };
          dependencies = [
            "generated/build_info.cc"
            "generated/build_info.hpp"
          ];
        }
      ];
    };

  buildInfoStrict = mkBuildInfoGenerator "strict";
  buildInfoScanned = mkBuildInfoGenerator "scanner";

  zlibLib = cpp.pkgConfig.makeLibrary {
    name = "zlib";
    packages = [ pkgs.zlib ];
    modules = [ "zlib" ];
  };

  mathLib = cpp.mkStaticLib {
    name = "math";
    inherit root includeDirs;
    sources = [ "src/math.cc" ];
    depsManifest = ./deps.json;
    publicIncludeDirs = includeDirs;
  };

  strict = cpp.mkExecutable {
    name = "simple-strict";
    inherit root includeDirs;
    sources = [ "src/main.cc" ];
    depsManifest = ./deps.json;
    libraries = [ mathLib zlibLib ];
    generators = [ buildInfoStrict ];
  };

  scannedManifest = cpp.mkDependencyScanner {
    name = "simple-scanner";
    inherit root sources;
    includeDirs = includeDirs;
    libraries = [ zlibLib ];
    generators = [ buildInfoScanned ];
  };

  scanned = cpp.mkExecutable {
    name = "simple-scanned";
    inherit root includeDirs;
    sources = [ "src/main.cc" ];
    scanner = scannedManifest;
    libraries = [ mathLib zlibLib ];
    generators = [ buildInfoScanned ];
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
    expectedLines = [
      "2 + 3 = 5"
      "4 * 5 = 20"
      "build summary: nixclang-simple v1.0.0 (mode=strict)"
      "zlib version: "
    ];
    name = "simple-strict";
  };

  scannedCheck = mkRunCheck {
    drv = scanned;
    expectedLines = [
      "2 + 3 = 5"
      "4 * 5 = 20"
      "build summary: nixclang-simple v1.0.0 (mode=scanner)"
      "zlib version: "
    ];
    name = "simple-scanned";
  };

in
{
  packages = {
    mathLib = mathLib.drv;
    inherit strict scanned;
  };

  checks = {
    simpleStrict = strictCheck;
    simpleScanned = scannedCheck;
  };

  inherit scannedManifest mathLib buildInfoStrict buildInfoScanned zlibLib;
}
