# Ninja module for nixnative
#
# Provides ninja build file generation and nix-ninja integration.
#
{ pkgs, lib, nix-ninja, nix-ninja-task, nixPackage, utils }:

let
  generate = import ./generate.nix { inherit lib utils; };

  wrapper = import ./wrapper.nix {
    inherit pkgs lib nix-ninja nix-ninja-task nixPackage;
  };

in
{
  # Re-export generation functions
  inherit (generate)
    escapeNinja
    formatIncludes
    formatDefines
    formatFlags
    mkCompileRule
    mkLinkExeRule
    mkLinkSharedRule
    mkArchiveRule
    mkBuildStatement
    generateExecutable
    generateStaticLib
    generateSharedLib
    ;

  # Re-export wrapper functions
  inherit (wrapper)
    mkNinjaDerivation
    mkNinjaTest
    ;

  # Check if nix-ninja is available
  isAvailable = nix-ninja != null && nix-ninja-task != null;
}
