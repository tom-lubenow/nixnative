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

  toolCore = import ./core/tool.nix { inherit lib; };

  # ==========================================================================
  # Utility Modules
  # ==========================================================================

  utils = import ./utils/utils.nix { inherit pkgs; };

  pkgConfigUtils = import ./utils/pkgconfig.nix { inherit pkgs lib; };

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

  gccCompilers = import ./compilers/gcc.nix {
    inherit pkgs lib;
    inherit (compilerCore) mkCompiler gccFlagTranslators;
  };

  zigCompilers = import ./compilers/zig.nix {
    inherit pkgs lib;
    inherit (compilerCore) mkCompiler zigFlagTranslators;
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

  goldLinkers = import ./linkers/gold.nix {
    inherit pkgs lib;
    inherit (linkerCore) mkLinker goldCapabilities;
  };

  gnuLdLinkers = import ./linkers/ld.nix {
    inherit pkgs lib;
    inherit (linkerCore) mkLinker ldCapabilities;
  };

  darwinLinkers = import ./linkers/darwin-ld.nix {
    inherit pkgs lib;
    inherit (linkerCore) mkLinker darwinLdCapabilities;
  };

  # ==========================================================================
  # Tool Plugins
  # ==========================================================================

  protobufTool = import ./tools/protobuf.nix {
    inherit pkgs lib;
    inherit (toolCore) mkTool;
  };

  jinjaTool = import ./tools/jinja.nix {
    inherit pkgs lib;
    inherit (toolCore) mkTool;
  };

  # ==========================================================================
  # Assembled Collections
  # ==========================================================================

  compilers = {
    # Clang variants
    inherit (clangCompilers) clang clang17 clang18 clang19;

    # GCC variants
    inherit (gccCompilers) gcc gcc12 gcc13 gcc14;

    # Zig CC (C/C++ via Zig)
    inherit (zigCompilers) zig zigCC;
    zigCross = zigCompilers.crossTargets;
  };

  linkers = {
    # LLD variants
    inherit (lldLinkers) lld lld17 lld18 lld19;

    # Mold (Linux only, fast)
    inherit (moldLinkers) mold;

    # Gold (Linux only)
    gold = goldLinkers.gold;

    # GNU ld (Linux only)
    ld = gnuLdLinkers.ld;
    gnuLd = gnuLdLinkers.gnuLd;
    bfd = gnuLdLinkers.bfd;

    # Darwin ld64
    darwinLd = darwinLinkers.darwinLd;

    # Default linker for platform
    default =
      if pkgs.stdenv.targetPlatform.isDarwin
      then darwinLinkers.darwinLd
      else lldLinkers.lld;
  };

  # Assembled tool plugins
  tools = {
    # Protobuf code generation
    inherit (protobufTool) protobuf grpc;

    # Jinja2 template code generation
    inherit (jinjaTool) jinja configHeader enumGenerator;
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

      # Determine which getBintools helper to use based on compiler name
      bintools =
        if lib.hasPrefix "gcc" compiler.name then gccCompilers.getBintools compiler
        else if lib.hasPrefix "zig" compiler.name then zigCompilers.getBintools compiler
        else clangCompilers.getBintools compiler;  # Default to clang bintools

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
    # ========================================================================
    # Clang Toolchains
    # ========================================================================

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

    # Clang + Gold
    clang-gold =
      if goldLinkers.isAvailable
      then mkToolchain {
        compiler = compilers.clang;
        linker = linkers.gold;
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

    # ========================================================================
    # GCC Toolchains
    # ========================================================================

    # GCC + Mold (fast linking)
    gcc-mold =
      if moldLinkers.isAvailable && compilers.gcc != null
      then mkToolchain {
        compiler = compilers.gcc;
        linker = linkers.mold;
      }
      else null;

    # GCC + Gold
    gcc-gold =
      if goldLinkers.isAvailable && compilers.gcc != null
      then mkToolchain {
        compiler = compilers.gcc;
        linker = linkers.gold;
      }
      else null;

    # GCC + GNU ld (classic)
    gcc-ld =
      if gnuLdLinkers.isAvailable && compilers.gcc != null
      then mkToolchain {
        compiler = compilers.gcc;
        linker = linkers.ld;
      }
      else null;

    # GCC + LLD
    gcc-lld =
      if compilers.gcc != null
      then mkToolchain {
        compiler = compilers.gcc;
        linker = linkers.lld;
      }
      else null;

    # ========================================================================
    # Zig Toolchains
    # ========================================================================

    # Zig CC (uses Zig's internal linker)
    zig-native =
      if compilers.zig != null
      then mkToolchain {
        compiler = compilers.zig;
        linker = linkers.lld;  # Zig typically uses LLD internally
      }
      else null;

    # ========================================================================
    # Default Toolchain
    # ========================================================================

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

  # High-level API (Option B style)
  api = import ./builders/api.nix {
    inherit lib compilers linkers mkToolchain helpers;
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
  inherit compilers linkers toolchains tools;

  # Tool factory (for custom tools)
  inherit (toolCore) mkTool;

  # Capability presets (for custom linkers)
  linkerCapabilities = {
    inherit (linkerCore) lldCapabilities moldCapabilities goldCapabilities ldCapabilities darwinLdCapabilities;
  };

  # Darwin helpers
  darwin = darwinLinkers;

  # ==========================================================================
  # High-Level API (recommended)
  # ==========================================================================
  #
  # These functions accept `compiler` and `linker` as optional string params
  # with sensible defaults (clang + platform default linker).
  #
  # Usage:
  #   native.executable { name = "app"; sources = [...]; }
  #   native.staticLib { compiler = "gcc"; linker = "mold"; ... }
  #
  inherit (api) executable staticLib sharedLib headerOnly devShell test;

  # Expose resolvers for advanced use
  inherit (api) resolveCompiler resolveLinker;

  # ==========================================================================
  # Low-Level Build Functions (explicit toolchain)
  # ==========================================================================
  #
  # These require an explicit `toolchain` argument. Use these when you need
  # full control or are building custom toolchains.
  #
  # Usage:
  #   native.mkExecutable {
  #     toolchain = native.mkToolchain { compiler = ...; linker = ...; };
  #     name = "app";
  #     ...
  #   }
  #
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

  # pkg-config integration
  pkgConfig = pkgConfigUtils;

  # ==========================================================================
  # Version Info
  # ==========================================================================

  version = "0.1.0";
  name = "nixnative";
}
