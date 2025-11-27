# nixnative - Multi-compiler, multi-linker C/C++ build system for Nix
#
# Main entry point. Import this to get access to all nixnative functionality.
#
# Usage:
#   let
#     native = nixnative.lib.native { inherit pkgs; };
#   in
#   native.mkExecutable { ... }
#
{ pkgs, lib ? pkgs.lib }:

let
  # ==========================================================================
  # Core Modules
  # ==========================================================================

  flags = import ./core/flags.nix { inherit lib; };

  compilerCore = import ./core/compiler.nix { inherit lib flags; };

  linkerCore = import ./core/linker.nix { inherit lib; };

  toolchainCore = import ./core/toolchain.nix { inherit lib flags; };

  platformUtils = import ./core/platform.nix { inherit lib; };

  # ==========================================================================
  # Utility Modules
  # ==========================================================================

  utils = import ./utils/utils.nix { inherit pkgs; };

  # ==========================================================================
  # Scanner Modules
  # ==========================================================================

  manifest = import ./scanner/manifest.nix { inherit lib utils; };

  scanner = import ./scanner/scanner.nix {
    inherit pkgs lib utils manifest;
  };

  # ==========================================================================
  # Compiler Implementations
  # ==========================================================================

  clangCompilers = import ./compilers/clang.nix {
    inherit pkgs lib;
    inherit (compilerCore) mkCompiler commonFlagTranslators;
  };

  # ==========================================================================
  # Linker Implementations
  # ==========================================================================

  lldLinkers = import ./linkers/lld.nix {
    inherit pkgs lib;
    inherit (linkerCore) mkLinker lldCapabilities;
  };

  moldLinkers = import ./linkers/mold.nix {
    inherit pkgs lib;
    inherit (linkerCore) mkLinker moldCapabilities;
  };

  darwinLinkers = import ./linkers/darwin-ld.nix {
    inherit pkgs lib;
    inherit (linkerCore) mkLinker darwinLdCapabilities;
  };

  # ==========================================================================
  # Assembled Collections
  # ==========================================================================

  compilers = {
    inherit (clangCompilers) clang clang17 clang18 clang19;
    # Future: gcc, zig
  };

  linkers = {
    inherit (lldLinkers) lld lld17 lld18 lld19;
    inherit (moldLinkers) mold;
    darwinLd = darwinLinkers.darwinLd;
    # Aliases
    default =
      if pkgs.stdenv.targetPlatform.isDarwin
      then darwinLinkers.darwinLd
      else lldLinkers.lld;
  };

  # ==========================================================================
  # Toolchain Factory
  # ==========================================================================

  # Create a toolchain from compiler + linker
  mkToolchain = { compiler, linker ? null, ... }@args:
    let
      # Use default linker if not specified
      resolvedLinker =
        if linker != null then linker
        else linkers.default;

      # Get bintools from clang helper
      bintools = clangCompilers.getBintools compiler;

      targetPlatform = pkgs.stdenv.targetPlatform;

      # Darwin-specific configuration
      darwinConfig =
        if targetPlatform.isDarwin then {
          sdkPath = pkgs.apple-sdk.sdkroot;
          deploymentTarget = targetPlatform.darwinMinVersion or "11.0";
        }
        else {};
    in
    toolchainCore.mkToolchain ({
      name = toolchainCore.makeToolchainName compiler resolvedLinker;
      inherit compiler targetPlatform;
      linker = resolvedLinker;
      inherit (bintools) ar ranlib nm objcopy strip;
    } // darwinConfig // (builtins.removeAttrs args [ "compiler" "linker" ]));

  # ==========================================================================
  # Pre-Built Toolchains
  # ==========================================================================

  toolchains = {
    # Clang + LLD (Linux default)
    clang-lld = mkToolchain {
      compiler = compilers.clang;
      linker = linkers.lld;
    };

    # Clang + Mold (fast linking on Linux)
    clang-mold =
      if moldLinkers.isAvailable
      then mkToolchain {
        compiler = compilers.clang;
        linker = linkers.mold;
      }
      else null;

    # Clang + Darwin ld64 (macOS)
    clang-darwin =
      if darwinLinkers.isAvailable
      then mkToolchain {
        compiler = compilers.clang;
        linker = linkers.darwinLd;
      }
      else null;

    # Default toolchain for current platform
    default =
      if pkgs.stdenv.targetPlatform.isDarwin
      then toolchains.clang-darwin
      else toolchains.clang-lld;
  };

  # ==========================================================================
  # Builder Modules
  # ==========================================================================

  compile = import ./builders/compile.nix {
    inherit pkgs lib utils;
  };

  link = import ./builders/link.nix {
    inherit pkgs lib;
  };

  context = import ./builders/context.nix {
    inherit pkgs lib utils flags compile scanner;
  };

  helpers = import ./builders/helpers.nix {
    inherit pkgs lib utils context link;
  };

in {
  # ==========================================================================
  # Public API
  # ==========================================================================

  # Core factories
  inherit (compilerCore) mkCompiler commonFlagTranslators gccFlagTranslators zigFlagTranslators;
  inherit (linkerCore) mkLinker;
  inherit (toolchainCore) validateToolchain getCapabilities toolchainSupports;

  # Local mkToolchain with defaults (see let block)
  inherit mkToolchain;

  # Flag system
  inherit flags;

  # Platform utilities
  platform = platformUtils;

  # Assembled collections
  inherit compilers linkers toolchains;

  # Capability presets (for custom linkers)
  linkerCapabilities = {
    inherit (linkerCore) lldCapabilities moldCapabilities goldCapabilities ldCapabilities darwinLdCapabilities;
  };

  # Darwin helpers
  darwin = darwinLinkers;

  # ==========================================================================
  # High-Level Build Functions
  # ==========================================================================

  # Primary builders
  inherit (helpers) mkExecutable mkStaticLib mkSharedLib mkHeaderOnly;
  inherit (helpers) mkDevShell mkTest;

  # Lower-level builders
  inherit (context) mkBuildContext;
  inherit (compile) compileTranslationUnit generateCompileCommands;
  inherit (link) mkLinkStep linkExecutable linkSharedLibrary createStaticArchive;

  # Scanner and manifest utilities
  inherit (scanner) mkDependencyScanner processTools;
  inherit (manifest) mkManifest emptyManifest mergeManifests;

  # Utilities (for advanced users)
  inherit utils;

  # ==========================================================================
  # Version Info
  # ==========================================================================

  version = "0.1.0";
  name = "nixnative";
}
