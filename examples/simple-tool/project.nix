{ pkgs, native }:

let
  # Read version from file
  versionStr = builtins.readFile ./version.txt;
  # builtins.split returns alternating strings and match groups (lists), so filter to strings only
  versionParts = builtins.filter builtins.isString
    (builtins.split "\\." (pkgs.lib.removeSuffix "\n" versionStr));

  # ==========================================================================
  # NEW WAY: Using mkGeneratedSources (recommended)
  # ==========================================================================

  # Generate version header using a simple derivation
  versionDrv = pkgs.writeTextDir "version.h" ''
    #pragma once

    #define VERSION_MAJOR ${builtins.elemAt versionParts 0}
    #define VERSION_MINOR ${builtins.elemAt versionParts 1}
    #define VERSION_PATCH ${builtins.elemAt versionParts 2}
    #define VERSION_STRING "${pkgs.lib.removeSuffix "\n" versionStr}"
  '';

  # Wrap it with mkGeneratedSources - much simpler!
  versionTool = native.mkGeneratedSources {
    name = "version-header";
    drv = versionDrv;
    headers = [ "version.h" ];
  };

  # App using the simplified tool API
  appInline = native.executable {
    name = "simple-tool-inline";
    root = ./.;
    sources = [ "main.cc" ];
    tools = [ versionTool ];
  };

  # ==========================================================================
  # OLD WAY: Manual attrset (still works, for reference)
  # ==========================================================================

  # Manual attrset approach (more verbose, but still supported)
  versionGeneratorManual = {
    name = "version-generator";
    headers = [
      { rel = "version.h"; store = "${versionDrv}/version.h"; }
    ];
    includeDirs = [ { path = versionDrv; } ];
  };

  appManual = native.executable {
    name = "simple-tool-manual";
    root = ./.;
    sources = [ "main.cc" ];
    tools = [ versionGeneratorManual ];
  };

in {
  inherit appInline appManual;
  simpleToolExample = appInline;
}
