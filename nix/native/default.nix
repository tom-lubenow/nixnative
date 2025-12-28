# nixnative - Incremental C/C++ builds using Nix dynamic derivations
#
# Main entry point. Import this to get access to all nixnative functionality.
#
# Requires Nix with dynamic derivations support:
#   experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
#
# Usage:
#   let
#     native = nixnative.lib.native { inherit pkgs nixPackage; };
#   in
#   native.executable { ... }
#
{
  pkgs,
  lib ? pkgs.lib,
  # Nix package with dynamic derivations support (optional, defaults to pkgs.nix)
  nixPackage ? pkgs.nix,
}:

let
  # ==========================================================================
  # Utility Modules (loaded first - needed by other modules)
  # ==========================================================================

  utils = import ./utils/utils.nix { inherit pkgs; };

  pkgConfigUtils = import ./utils/pkgconfig.nix { inherit pkgs lib; };

  # ==========================================================================
  # Core Modules
  # ==========================================================================

  flags = import ./core/flags.nix { inherit lib; };

  compilerCore = import ./core/compiler.nix { inherit lib flags; };

  linkerCore = import ./core/linker.nix { inherit lib; };

  platformUtils = import ./core/platform.nix { inherit lib; };

  language = import ./core/language.nix { inherit lib; };

  toolchainCore = import ./core/toolchain.nix {
    inherit lib flags language;
    platform = platformUtils;
  };

  toolCore = import ./core/tool.nix { inherit pkgs lib utils; };

  testLibCore = import ./core/testlib.nix { inherit lib; };

  # ==========================================================================
  # Scanner Modules
  # ==========================================================================

  manifest = import ./scanner/manifest.nix { inherit lib utils; };

  parsers = import ./scanner/parsers.nix { inherit lib; };

  scanner = import ./scanner/scanner.nix {
    inherit
      pkgs
      lib
      utils
      manifest
      language
      parsers
      ;
  };

  # ==========================================================================
  # Dynamic Derivations Module (Experimental)
  # ==========================================================================

  dynamic = import ./dynamic {
    inherit pkgs lib utils scanner nixPackage;
  };

  # ==========================================================================
  # Compiler Implementations
  # ==========================================================================

  clangCompilers = import ./compilers/clang.nix {
    inherit pkgs;
    inherit (compilerCore) mkCompiler commonFlagTranslators mkGccStyleScanner;
  };

  gccCompilers = import ./compilers/gcc.nix {
    inherit pkgs;
    inherit (compilerCore) mkCompiler gccFlagTranslators mkGccStyleScanner;
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
    inherit pkgs;
    inherit (linkerCore) mkLinker;
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

  binaryBlobTool = import ./tools/binary-blob.nix {
    inherit pkgs lib;
    inherit (toolCore) mkTool;
  };

  # ==========================================================================
  # Test Library Implementations
  # ==========================================================================

  gtestTestLibs = import ./testlibs/gtest.nix {
    inherit pkgs lib;
    inherit (testLibCore) mkTestLib;
  };

  catch2TestLibs = import ./testlibs/catch2.nix {
    inherit pkgs lib;
    inherit (testLibCore) mkTestLib;
  };

  doctestTestLibs = import ./testlibs/doctest.nix {
    inherit pkgs lib;
    inherit (testLibCore) mkTestLib;
  };

  # ==========================================================================
  # LSP Configurations
  # ==========================================================================

  lsps = import ./lsps { inherit pkgs lib; };

  # ==========================================================================
  # Assembled Collections
  # ==========================================================================

  compilers = {
    # Clang variants (each has .c, .cpp, .bintools)
    inherit (clangCompilers)
      clang
      clang17
      clang18
      clang19
      ;

    # GCC variants (each has .c, .cpp, .bintools)
    inherit (gccCompilers)
      gcc
      gcc12
      gcc13
      gcc14
      ;
  };

  linkers = {
    # LLD variants
    inherit (lldLinkers)
      lld
      lld17
      lld18
      lld19
      ;

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
    default = if pkgs.stdenv.targetPlatform.isDarwin then darwinLinkers.darwinLd else lldLinkers.lld;
  };

  # Assembled tool plugins
  tools = {
    # Protobuf code generation
    inherit (protobufTool) protobuf grpc;

    # Jinja2 template code generation
    inherit (jinjaTool) jinja configHeader enumGenerator;

    # Binary blob embedding (objcopy replacement)
    inherit (binaryBlobTool) binaryBlob;
  };

  # Assembled test libraries
  testLibs = {
    # GoogleTest
    inherit (gtestTestLibs) gtest gmock;

    # Catch2
    inherit (catch2TestLibs) catch2;

    # doctest
    inherit (doctestTestLibs) doctest;
  };

  # ==========================================================================
  # Toolchain Factory
  # ==========================================================================

  # Create a toolchain from languages map + linker
  #
  # Usage:
  #   mkToolchain {
  #     languages = {
  #       c = native.compilers.clang.c;
  #       cpp = native.compilers.clang.cpp;
  #     };
  #     linker = native.linkers.lld;
  #     bintools = native.compilers.clang.bintools;
  #   }
  #
  mkToolchain =
    {
      languages,
      linker ? null,
      bintools ? null,
      ...
    }@args:
    let
      # Use default linker if not specified
      resolvedLinker = if linker != null then linker else linkers.default;

      # Try to infer bintools from the first language's parent compiler
      # (users can override by passing bintools explicitly)
      inferredBintools =
        if bintools != null then bintools
        else
          # Default to clang bintools
          clangCompilers.clang.bintools;

      targetPlatform = pkgs.stdenv.targetPlatform;
    in
    toolchainCore.mkToolchain (
      {
        inherit languages targetPlatform;
        linker = resolvedLinker;
        bintools = inferredBintools;
      }
      // (builtins.removeAttrs args [
        "languages"
        "linker"
        "bintools"
      ])
    );

  # ==========================================================================
  # Pre-Built Toolchains
  # ==========================================================================

  toolchains = {
    # ========================================================================
    # Clang Toolchains
    # ========================================================================

    # Clang + LLD (Linux default)
    clang-lld = mkToolchain {
      languages = {
        c = compilers.clang.c;
        cpp = compilers.clang.cpp;
      };
      linker = linkers.lld;
      bintools = compilers.clang.bintools;
    };

    # Clang + Mold (fast linking on Linux)
    clang-mold =
      if moldLinkers.isAvailable then
        mkToolchain {
          languages = {
            c = compilers.clang.c;
            cpp = compilers.clang.cpp;
          };
          linker = linkers.mold;
          bintools = compilers.clang.bintools;
        }
      else
        null;

    # Clang + Gold
    clang-gold =
      if goldLinkers.isAvailable then
        mkToolchain {
          languages = {
            c = compilers.clang.c;
            cpp = compilers.clang.cpp;
          };
          linker = linkers.gold;
          bintools = compilers.clang.bintools;
        }
      else
        null;

    # Clang + Darwin ld64 (macOS)
    clang-darwin =
      if darwinLinkers.isAvailable then
        mkToolchain {
          languages = {
            c = compilers.clang.c;
            cpp = compilers.clang.cpp;
          };
          linker = linkers.darwinLd;
          bintools = compilers.clang.bintools;
        }
      else
        null;

    # ========================================================================
    # GCC Toolchains
    # ========================================================================

    # GCC + Mold (fast linking)
    gcc-mold =
      if moldLinkers.isAvailable && compilers.gcc != null then
        mkToolchain {
          languages = {
            c = compilers.gcc.c;
            cpp = compilers.gcc.cpp;
          };
          linker = linkers.mold;
          bintools = compilers.gcc.bintools;
        }
      else
        null;

    # GCC + Gold
    gcc-gold =
      if goldLinkers.isAvailable && compilers.gcc != null then
        mkToolchain {
          languages = {
            c = compilers.gcc.c;
            cpp = compilers.gcc.cpp;
          };
          linker = linkers.gold;
          bintools = compilers.gcc.bintools;
        }
      else
        null;

    # GCC + GNU ld (classic)
    gcc-ld =
      if gnuLdLinkers.isAvailable && compilers.gcc != null then
        mkToolchain {
          languages = {
            c = compilers.gcc.c;
            cpp = compilers.gcc.cpp;
          };
          linker = linkers.ld;
          bintools = compilers.gcc.bintools;
        }
      else
        null;

    # GCC + LLD
    gcc-lld =
      if compilers.gcc != null then
        mkToolchain {
          languages = {
            c = compilers.gcc.c;
            cpp = compilers.gcc.cpp;
          };
          linker = linkers.lld;
          bintools = compilers.gcc.bintools;
        }
      else
        null;

    # ========================================================================
    # Default Toolchain
    # ========================================================================

    # Default toolchain for current platform
    default =
      if pkgs.stdenv.targetPlatform.isDarwin then toolchains.clang-darwin else toolchains.clang-lld;
  };

  # ==========================================================================
  # Builder Modules
  # ==========================================================================

  compile = import ./builders/compile.nix {
    inherit pkgs lib utils;
  };

  link = import ./builders/link.nix {
    inherit pkgs lib;
    platform = platformUtils;
  };

  context = import ./builders/context.nix {
    inherit
      pkgs
      lib
      utils
      flags
      compile
      scanner
      dynamic
      ;
  };

  helpers = import ./builders/helpers.nix {
    inherit
      pkgs
      lib
      utils
      context
      link
      dynamic
      ;
    platform = platformUtils;
  };

  # High-level API (Option B style)
  api = import ./builders/api.nix {
    inherit
      lib
      compilers
      linkers
      mkToolchain
      helpers
      ;
  };

in
{
  # ==========================================================================
  # Public API
  # ==========================================================================

  # Core factories
  inherit (compilerCore) mkCompiler commonFlagTranslators gccFlagTranslators mkGccStyleScanner validateScanner;
  inherit (linkerCore) mkLinker;
  inherit (toolchainCore) validateToolchain getCapabilities toolchainSupports;

  # Local mkToolchain with defaults (see let block)
  inherit mkToolchain;

  # Flag system
  inherit flags;

  # Platform utilities
  platform = platformUtils;

  # Language detection and registry
  inherit language;

  # Assembled collections
  inherit
    compilers
    linkers
    toolchains
    tools
    testLibs
    ;

  # Tool factory (for custom tools)
  inherit (toolCore) mkTool;

  # Test library factory (for custom test frameworks)
  inherit (testLibCore) mkTestLib;

  # Capability presets (for custom linkers)
  linkerCapabilities = {
    inherit (linkerCore)
      lldCapabilities
      moldCapabilities
      goldCapabilities
      ldCapabilities
      ;
  };

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
  inherit (api)
    executable
    staticLib
    sharedLib
    headerOnly
    devShell
    test
    archive
    ;

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
  inherit (helpers)
    mkExecutable
    mkStaticLib
    mkSharedLib
    mkHeaderOnly
    mkArchive
    ;
  inherit (helpers) mkDevShell mkTest;

  # Lower-level builders
  inherit (context) mkBuildContext;
  inherit (compile) compileTranslationUnit generateCompileCommands;
  inherit (link)
    mkLinkStep
    linkExecutable
    linkSharedLibrary
    createStaticArchive
    ;

  # Tool plugin processing
  inherit (scanner) processTools;
  inherit (manifest) mkManifest emptyManifest mergeManifests;

  # Dynamic derivations internals (for advanced use)
  inherit (dynamic)
    hasDynamicDerivations
    mkDynamicDriver
    mkDynamicBuildContext
    ;

  # Utilities (for advanced users)
  inherit utils;

  # pkg-config integration
  pkgConfig = pkgConfigUtils;

  # LSP configurations (clangd, etc.)
  inherit lsps;

  # ==========================================================================
  # Version Info
  # ==========================================================================

  version = "0.1.0";
  name = "nixnative";
}
