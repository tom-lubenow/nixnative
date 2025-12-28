# Dynamic link step for nixnative
#
# Provides functions to get references to dynamic derivation outputs.
#
# The driver derivation (with outputHashMode = "text") outputs a .drv file
# for the link step. We use builtins.outputOf to get a placeholder that
# Nix resolves at build time by:
# 1. Building the driver to get the link .drv
# 2. Building the link .drv to get the final artifact
#
{
  pkgs,
  lib,
}:

let
  inherit (lib) concatStringsSep;

in
rec {
  # ==========================================================================
  # Dynamic Output Reference
  # ==========================================================================

  # Get a reference to the final linked output from a dynamic driver
  #
  # The driver outputs a .drv file (text mode). This function returns
  # a placeholder that references the "out" output of that .drv.
  #
  # Arguments:
  #   driverDrv - The driver derivation from mkDynamicDriver
  #
  # Returns:
  #   A string placeholder that Nix resolves at build time
  #
  getDynamicOutput = driverDrv:
    builtins.outputOf
      (builtins.unsafeDiscardOutputDependency driverDrv.outPath)
      "out";

  # Create a derivation that depends on a dynamic output
  #
  # This wraps the dynamic output reference in a simple derivation
  # that can be used with standard Nix tooling.
  #
  # Arguments:
  #   name      - Target name
  #   driverDrv - The driver derivation from mkDynamicDriver
  #
  mkDynamicExecutable =
    {
      name,
      driverDrv,
    }:
    let
      outputRef = getDynamicOutput driverDrv;
    in
    pkgs.runCommand name {
      # Reference the dynamic output
      dynamicOutput = outputRef;
    } ''
      mkdir -p $out
      cp -r "$dynamicOutput"/* $out/
    '';

  # Alias for backwards compatibility
  linkDynamicExecutable = mkDynamicExecutable;

  # Create a reference to a dynamic shared library
  mkDynamicSharedLibrary =
    {
      name,
      driverDrv,
    }:
    let
      outputRef = getDynamicOutput driverDrv;
    in
    pkgs.runCommand "shared-${name}" {
      dynamicOutput = outputRef;
    } ''
      mkdir -p $out
      cp -r "$dynamicOutput"/* $out/
    '' // {
      sharedName = "lib${name}.so";
      sharedLibrary = "${outputRef}/lib/lib${name}.so";
    };

  # Alias for backwards compatibility
  linkDynamicSharedLibrary = mkDynamicSharedLibrary;

  # Create a reference to a dynamic static archive
  mkDynamicStaticArchive =
    {
      name,
      driverDrv,
    }:
    let
      outputRef = getDynamicOutput driverDrv;
    in
    pkgs.runCommand "archive-${name}" {
      dynamicOutput = outputRef;
    } ''
      mkdir -p $out
      cp -r "$dynamicOutput"/* $out/
    '' // {
      archiveName = "lib${name}.a";
      archivePath = "${outputRef}/lib/lib${name}.a";
    };

  # Alias for backwards compatibility
  createDynamicStaticArchive = mkDynamicStaticArchive;
}
