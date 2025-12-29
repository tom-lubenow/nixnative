{ pkgs, native }:

let
  # Read version from file
  versionStr = builtins.readFile ./version.txt;
  # builtins.split returns alternating strings and match groups (lists), so filter to strings only
  versionParts = builtins.filter builtins.isString
    (builtins.split "\\." (pkgs.lib.removeSuffix "\n" versionStr));

  # Generate version header
  # Use writeTextDir to create a directory with the header, so include paths work
  versionHeaderDir = pkgs.writeTextDir "version.h" ''
    #pragma once

    #define VERSION_MAJOR ${builtins.elemAt versionParts 0}
    #define VERSION_MINOR ${builtins.elemAt versionParts 1}
    #define VERSION_PATCH ${builtins.elemAt versionParts 2}
    #define VERSION_STRING "${pkgs.lib.removeSuffix "\n" versionStr}"
  '';

  # Generator attrset - creates include directories for the generated header
  versionGenerator = {
    name = "version-generator";
    headers = [
      { rel = "version.h"; store = "${versionHeaderDir}/version.h"; }
    ];
    includeDirs = [ { path = versionHeaderDir; } ];
  };

  # App using the generator
  appInline = native.executable {
    name = "simple-tool-inline";
    root = ./.;
    sources = [ "main.cc" ];
    tools = [ versionGenerator ];
  };

in {
  inherit appInline;
  simpleToolExample = appInline;
}
