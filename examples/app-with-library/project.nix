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
      # Only capture the specific template files needed, not the entire root!
      # This ensures changes to other files (like math.cc) don't invalidate this tool.
      hppTemplate = builtins.path { path = root + "/templates/build_info.hpp.j2"; };
      ccTemplate = builtins.path { path = root + "/templates/build_info.cc.j2"; };
      renderDrv = pkgs.runCommand "build-info-${mode}"
        {
          buildInputs = [ pythonEnv ];
        }
        ''
          set -euo pipefail
          mkdir -p "$out/generated"
          ${pythonEnv}/bin/python - "$out" ${lib.escapeShellArg mode} ${hppTemplate} ${ccTemplate} <<'PY'
import pathlib
import sys
from jinja2 import Template

out_dir = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
hpp_template = pathlib.Path(sys.argv[3])
cc_template = pathlib.Path(sys.argv[4])

project = "nixnative-simple"
version = {"major": 1, "minor": 0, "patch": 0}

def render(template_path, output_rel):
    tpl = Template(template_path.read_text())
    rendered = tpl.render(projectName=project, mode=mode, version=version)
    target = out_dir / output_rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(rendered)

render(hpp_template, pathlib.Path("generated/build_info.hpp"))
render(cc_template, pathlib.Path("generated/build_info.cc"))
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
      outputs = [
        { rel = "generated/build_info.hpp"; path = "${renderDrv}/generated/build_info.hpp"; }
        { rel = "generated/build_info.cc"; path = "${renderDrv}/generated/build_info.cc"; }
      ];
      includeDirs = [ includeDir ];
      public = {
        includeDirs = [ includeDir ];
        defines = [ ];
        compileFlags = [ ];
        linkFlags = [ ];
      };
      evalInputs = [ renderDrv ];
    };

  buildInfoTool = mkBuildInfoTool "dynamic";

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
    publicIncludeDirs = includeDirs;
  };

  # Main executable with tool plugin
  app = native.executable {
    name = "simple-app";
    inherit root includeDirs;
    sources = appSources;
    libraries = [ mathLib zlibLib ];
    tools = [ buildInfoTool ];
  };

in {
  inherit mathLib app;
}
