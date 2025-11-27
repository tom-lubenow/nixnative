# LSP configurations for nixnative
#
# This module provides functions to configure Language Server Protocol
# servers for use with nixnative projects.
#
# Usage:
#   let
#     native = nixnative.lib.native { inherit pkgs; };
#     clangd = native.lsps.clangd { targets = [ app ]; };
#   in
#   pkgs.mkShell {
#     packages = clangd.packages;
#     shellHook = clangd.shellHook;
#   };
#
{ pkgs, lib }:

let
  clangdModule = import ./clangd.nix { inherit pkgs lib; };
in {
  # clangd configuration
  # Creates a properly configured clangd with merged compile_commands.json
  inherit (clangdModule) mkClangd clangd;
}
