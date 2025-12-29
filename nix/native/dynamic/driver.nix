# Dynamic derivations feature detection for nixnative
#
# This module provides feature detection for Nix dynamic derivations.
# The actual compilation and linking primitives are in compile.nix, link.nix, and archive.nix.
#
# Requirements:
#   experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
#
{
  pkgs,
  lib,
  utils,
  nixPackage ? pkgs.nix,
}:

{
  # ==========================================================================
  # Feature Detection
  # ==========================================================================

  # Check if dynamic derivations are available
  # This checks for builtins.outputOf which is the key primitive
  hasDynamicDerivations = builtins ? outputOf;

  # Validate that dynamic derivations are available
  requireDynamicDerivations =
    if builtins ? outputOf then
      true
    else
      throw ''
        nixnative: dynamic mode requires Nix with 'dynamic-derivations' experimental feature.
        Add to your nix.conf:
          experimental-features = nix-command flakes dynamic-derivations ca-derivations recursive-nix
      '';
}
