# Dynamic derivations module for nixnative
#
# This module provides support for Nix dynamic derivations, eliminating
# the need for IFD (Import From Derivation) during dependency scanning.
#
# Architecture:
#   - mkCompileSet: Compiles sources to objects (NO linking)
#   - mkLinkWrapper: Links object references into executable/shared library
#   - mkArchiveWrapper: Creates static archive from object references
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
  nixPackage ? pkgs.nix,
}:

let
  # Import sub-modules
  driver = import ./driver.nix { inherit pkgs lib utils nixPackage; };

  compile = import ./compile.nix { inherit pkgs lib utils nixPackage; };

  link = import ./link.nix { inherit pkgs lib utils nixPackage; };

  archive = import ./archive.nix { inherit pkgs lib utils nixPackage; };

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
  # Compilation Primitives
  # ==========================================================================

  # Compile sources to objects (NO linking)
  inherit (compile)
    mkCompileWrapper      # Single source -> object wrapper
    mkCompileSet          # Multiple sources -> { wrappers, objectRefs, tus }
    ;

  # ==========================================================================
  # Link Primitives
  # ==========================================================================

  # Link object references into final artifacts
  inherit (link)
    mkLinkWrapper         # Generic linker (objectRefs -> executable/sharedLib)
    mkExecutableLink      # Convenience: objectRefs -> executable
    mkSharedLibLink       # Convenience: objectRefs -> shared library
    ;

  # ==========================================================================
  # Archive Primitives
  # ==========================================================================

  # Create static archives from object references
  inherit (archive)
    mkArchiveWrapper      # objectRefs -> .a archive
    ;
}
