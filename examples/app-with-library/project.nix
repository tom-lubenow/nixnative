{ pkgs, native }:

let
  lib = pkgs.lib;
  root = ./.;
  includeDirs = [ "include" ];
  appSources = [ "src/main.cc" ];
  libSources = [ "src/math.cc" ];

  # Custom build-info generator (tool plugin)
  mkBuildInfoTool = mode:
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

project = "nixnative-simple"
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
        units."generated/build_info.cc".dependencies = [
          "generated/build_info.cc"
          "generated/build_info.hpp"
        ];
      });
      includeDir = { path = "${renderDrv}"; };
    in
    {
      name = "build-info-${mode}";
      inherit manifest;
      headers = [{
        rel = "generated/build_info.hpp";
        path = "${renderDrv}/generated/build_info.hpp";
        store = "${renderDrv}/generated/build_info.hpp";
      }];
      sources = [{
        rel = "generated/build_info.cc";
        path = "${renderDrv}/generated/build_info.cc";
        store = "${renderDrv}/generated/build_info.cc";
      }];
      includeDirs = [ includeDir ];
      public = {
        includeDirs = [ includeDir ];
        defines = [ ];
        cxxFlags = [ ];
        linkFlags = [ ];
      };
      evalInputs = [ renderDrv ];
    };

  buildInfoStrict = mkBuildInfoTool "strict";
  buildInfoScanned = mkBuildInfoTool "scanner";

  # Wrap zlib via pkg-config
  zlibLib = native.pkgConfig.makeLibrary {
    name = "zlib";
    packages = [ pkgs.zlib ];
    modules = [ "zlib" ];
  };

  # Static library using high-level API
  mathLib = native.staticLib {
    name = "math";
    inherit root includeDirs;
    sources = libSources;
    depsManifest = ./.deps.nix;
    publicIncludeDirs = includeDirs;
  };

  # Executable with pre-computed manifest and tools
  strict = native.executable {
    name = "simple-strict";
    inherit root includeDirs;
    sources = appSources;
    depsManifest = ./.deps.nix;
    libraries = [ mathLib zlibLib ];
    tools = [ buildInfoStrict ];
  };

  # Executable with auto-scanned dependencies
  scanned = native.executable {
    name = "simple-scanned";
    inherit root includeDirs;
    sources = appSources;
    libraries = [ mathLib zlibLib ];
    tools = [ buildInfoScanned ];
  };

in {
  mathLib = mathLib;
  strict = strict;
  scanned = scanned;
}
