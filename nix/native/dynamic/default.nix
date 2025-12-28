# Dynamic derivations module for nixnative
#
# This module provides support for Nix dynamic derivations, eliminating
# the need for IFD (Import From Derivation) during dependency scanning.
#
# Usage:
#   native.executable {
#     name = "app";
#     sources = [ "src/*.cc" ];
#     dynamic = true;  # Enable dynamic derivations mode
#   }
#
# Requirements:
#   Nix must be configured with:
#   experimental-features = nix-command flakes dynamic-derivations ca-derivations recursive-nix
#
{
  pkgs,
  lib,
  utils,
  scanner,
  nixPackage ? pkgs.nix,
}:

let
  # Import sub-modules
  driver = import ./driver.nix { inherit pkgs lib utils nixPackage; };

  dynamicContext = import ./context.nix {
    inherit pkgs lib utils driver scanner;
  };

  dynamicLink = import ./link.nix { inherit pkgs lib; };

in
{
  # ==========================================================================
  # Feature Detection
  # ==========================================================================

  # Check if dynamic derivations are available
  hasDynamicDerivations = driver.hasDynamicDerivations;

  # Validate that dynamic derivations are available (throws if not)
  requireDynamicDerivations = driver.requireDynamicDerivations;

  # ==========================================================================
  # Driver
  # ==========================================================================

  # Create a dynamic driver derivation
  inherit (driver)
    mkDynamicDriver
    mkDynamicOutputRef
    mkObjectsRef
    ;

  # ==========================================================================
  # Build Context
  # ==========================================================================

  # Create a dynamic build context (alternative to mkBuildContext)
  inherit (dynamicContext) mkDynamicBuildContext;

  # ==========================================================================
  # Link Steps
  # ==========================================================================

  # Link from dynamic driver output
  inherit (dynamicLink)
    getDynamicOutput
    mkDynamicExecutable
    mkDynamicSharedLibrary
    mkDynamicStaticArchive
    # Backwards compatibility aliases
    linkDynamicExecutable
    linkDynamicSharedLibrary
    createDynamicStaticArchive
    ;
}
