# project.nix - Build definition for the simple-tool example
#
# Demonstrates code generation using tool plugins.

{ pkgs, native }:

let
  versionStr = builtins.readFile ./version.txt;
  versionParts = builtins.filter builtins.isString
    (builtins.split "\\." (pkgs.lib.removeSuffix "\n" versionStr));

  versionDrv = pkgs.writeTextDir "version.h" ''
    #pragma once

    #define VERSION_MAJOR ${builtins.elemAt versionParts 0}
    #define VERSION_MINOR ${builtins.elemAt versionParts 1}
    #define VERSION_PATCH ${builtins.elemAt versionParts 2}
    #define VERSION_STRING "${pkgs.lib.removeSuffix "\n" versionStr}"
  '';

  versionTool = native.mkGeneratedSources {
    name = "version-header";
    drv = versionDrv;
    outputs = [ "version.h" ];
  };

  versionGeneratorManual = {
    name = "version-generator";
    outputs = [
      { rel = "version.h"; path = "${versionDrv}/version.h"; }
    ];
    includeDirs = [ { path = versionDrv; } ];
  };

  proj = native.project {
    root = ./.;
  };

  appInline = proj.executable {
    name = "simple-tool-inline";
    sources = [ "main.cc" ];
    tools = [ versionTool ];
  };

  appManual = proj.executable {
    name = "simple-tool-manual";
    sources = [ "main.cc" ];
    tools = [ versionGeneratorManual ];
  };

  testSimpleTool = native.test {
    name = "test-simple-tool";
    executable = appInline;
    expectedOutput = "Code generation working";
  };

in {
  packages = {
    inherit appInline appManual;
    simpleToolExample = appInline;
  };

  checks = {
    inherit testSimpleTool;
  };
}
