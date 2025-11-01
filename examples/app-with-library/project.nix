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
    let
      pythonEnv = pkgs.python3.withPackages (ps: [ ps.jinja2 ]);
      rootStore = builtins.path { path = root; name = "build-info-root"; };
      rootStr = builtins.toString rootStore;
      renderDrv = pkgs.runCommand "build-info-${mode}"
        {
          buildInputs = [ pythonEnv ];
        }
        ''
          set -euo pipefail
          mkdir -p "$out/generated"
          ${pythonEnv}/bin/python - "$out" ${lib.escapeShellArg mode} ${lib.escapeShellArg rootStr} <<'PY'
import pathlib
import sys
from jinja2 import Template

out_dir = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
root = pathlib.Path(sys.argv[3])

project = "nixclang-simple"
version = {"major": 1, "minor": 0, "patch": 0}

def render(template_rel, output_rel):
    template_path = root / template_rel
    tpl = Template(template_path.read_text())
    rendered = tpl.render(projectName=project, mode=mode, version=version)
    target = out_dir / output_rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(rendered)

render("templates/build_info.hpp.j2", pathlib.Path("generated/build_info.hpp"))
render("templates/build_info.cc.j2", pathlib.Path("generated/build_info.cc"))
PY
        '';
      manifest = pkgs.writeText "build-info-${mode}.manifest.json" (builtins.toJSON {
        schema = 1;
        units = {
          "generated/build_info.cc" = {
            dependencies = [
              "generated/build_info.cc"
              "generated/build_info.hpp"
            ];
          };
        };
      });
      includeDir = { path = "${renderDrv}"; };
    in
    {
      name = "build-info-${mode}";
      inherit manifest;
      headers = [
        {
          rel = "generated/build_info.hpp";
          path = "${renderDrv}/generated/build_info.hpp";
          store = "${renderDrv}/generated/build_info.hpp";
        }
      ];
      sources = [
        {
          rel = "generated/build_info.cc";
          path = "${renderDrv}/generated/build_info.cc";
          store = "${renderDrv}/generated/build_info.cc";
        }
      ];
      includeDirs = [ includeDir ];
      public = {
        includeDirs = [ includeDir ];
        defines = [ ];
        cxxFlags = [ ];
        linkFlags = [ ];
      };
      evalInputs = [ renderDrv ];
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

  scanned = cpp.mkExecutable {
    name = "simple-scanned";
    inherit root includeDirs;
    sources = [ "src/main.cc" ];
    scanner = cpp.mkDependencyScanner {
      name = "simple-scanner";
      inherit root sources includeDirs;
      libraries = [ zlibLib ];
      generators = [ buildInfoScanned ];
    };
    libraries = [ mathLib zlibLib ];
    generators = [ buildInfoScanned ];
  };

in {
  strict = strict;
  scanned = scanned;
  mathLib = mathLib.drv;
}
