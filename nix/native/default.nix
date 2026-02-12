# nixnative - Incremental C/C++ builds using nix-ninja
#
# Main entry point. Import this to get access to all nixnative functionality.
#
# Requires Nix with dynamic derivations and recursive-nix support:
#   experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
#
# Usage:
#   let
#     native = nixnative.lib.native {
#       inherit pkgs nixPackage;
#       inherit (nix-ninja.packages.${system}) nix-ninja nix-ninja-task;
#     };
#   in
#   native.executable { ... }
#
{
  pkgs,
  lib ? pkgs.lib,
  # Nix package with dynamic derivations support (optional, defaults to pkgs.nix)
  nixPackage ? pkgs.nix,
  # nix-ninja packages for incremental builds
  nix-ninja ? null,
  nix-ninja-task ? null,
  # Optional globset flake input for robust globbing
  globset ? null,
}:

let
  # ==========================================================================
  # Utility Modules (loaded first - needed by other modules)
  # ==========================================================================

  utils = import ./utils/utils.nix { inherit pkgs globset; };

  pkgConfigUtils = import ./utils/pkgconfig.nix { inherit pkgs lib; };

  # ==========================================================================
  # Core Modules
  # ==========================================================================

  compilerCore = import ./core/compiler.nix { inherit lib; };

  linkerCore = import ./core/linker.nix { inherit lib; };

  platformUtils = import ./core/platform.nix { inherit lib; };

  language = import ./core/language.nix { inherit lib; };

  toolchainCore = import ./core/toolchain.nix {
    inherit lib language;
    platform = platformUtils;
  };

  toolCore = import ./core/tool.nix { inherit pkgs lib utils language; };

  testLibCore = import ./core/testlib.nix { inherit lib; };


  # ==========================================================================
  # Ninja Module (nix-ninja integration)
  # ==========================================================================

  ninja = import ./ninja {
    inherit pkgs lib nixPackage nix-ninja nix-ninja-task utils;
  };

  # ==========================================================================
  # Compiler Implementations
  # ==========================================================================

  clangCompilers = import ./compilers/clang.nix {
    inherit pkgs;
    inherit (compilerCore) mkCompiler mkGccStyleScanner;
  };

  gccCompilers = import ./compilers/gcc.nix {
    inherit pkgs;
    inherit (compilerCore) mkCompiler mkGccStyleScanner;
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


  gnuLdLinkers = import ./linkers/ld.nix {
    inherit pkgs lib;
    inherit (linkerCore) mkLinker ldCapabilities;
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

  compilers = lib.filterAttrs (_: v: v != null) {
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

  linkers = lib.filterAttrs (_: v: v != null) {
    # LLD variants
    inherit (lldLinkers)
      lld
      lld17
      lld18
      lld19
      ;

    # Mold (Linux only, fast)
    inherit (moldLinkers) mold;

    # GNU ld
    ld = gnuLdLinkers.ld;
    gnuLd = gnuLdLinkers.gnuLd;
    bfd = gnuLdLinkers.bfd;

    # Default linker for platform
    default = lldLinkers.lld;
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

  # Create a toolset from languages map + linker
  #
  # Usage:
  #   mkToolset {
  #     languages = {
  #       c = native.compilers.clang.c;
  #       cpp = native.compilers.clang.cpp;
  #     };
  #     linker = native.linkers.lld;
  #     bintools = native.compilers.clang.bintools;
  #   }
  #
  mkToolset =
    {
      languages,
      linker ? null,
      bintools ? null,
      ...
    }@args:
    let
      # Use default linker if not specified
      resolvedLinker = if linker != null then linker else linkers.default;

      resolvedBintools =
        if bintools != null then
          bintools
        else
          throw "nixnative.mkToolchain: 'bintools' is required. Pass a bintools set (e.g., native.compilers.clang.bintools).";

    in
    toolchainCore.mkToolset (
      {
        inherit languages;
        linker = resolvedLinker;
        bintools = resolvedBintools;
      }
      // (builtins.removeAttrs args [
        "languages"
        "linker"
        "bintools"
      ])
    );

  # Create a policy with project/platform conventions.
  # targetPlatform defaults to the current stdenv target.
  mkPolicy =
    args:
    toolchainCore.mkPolicy (
      {
        targetPlatform = pkgs.stdenv.targetPlatform;
      }
      // args
    );

  # Create a toolchain by composing a toolset and a policy.
  # Compatibility: if toolset/policy are omitted, they are derived from
  # legacy mkToolchain fields.
  mkToolchain =
    {
      name ? null,
      toolset ? null,
      policy ? null,
      ...
    }@args:
    let
      hasLegacyToolsetFields = args ? languages || args ? linker || args ? bintools;
      hasLegacyPolicyFields = args ? targetPlatform || args ? runtimeInputs || args ? environment || args ? flags;

      _toolsetConflict =
        if toolset != null && hasLegacyToolsetFields then
          throw "nixnative.mkToolchain: pass either 'toolset' or legacy fields ('languages'/'linker'/'bintools'), not both."
        else
          null;

      _policyConflict =
        if policy != null && hasLegacyPolicyFields then
          throw "nixnative.mkToolchain: pass either 'policy' or legacy policy fields ('targetPlatform'/'runtimeInputs'/'environment'/'flags'), not both."
        else
          null;

      legacyToolsetArgs = builtins.removeAttrs args [
        "name"
        "toolset"
        "policy"
        "targetPlatform"
        "runtimeInputs"
        "environment"
        "flags"
      ];

      legacyPolicyArgs = builtins.removeAttrs args [
        "name"
        "toolset"
        "policy"
        "languages"
        "linker"
        "bintools"
      ];

      resolvedToolset = if toolset != null then toolset else mkToolset legacyToolsetArgs;
      resolvedPolicy = if policy != null then policy else mkPolicy legacyPolicyArgs;
    in
    builtins.seq _toolsetConflict (
      builtins.seq _policyConflict (
        toolchainCore.mkToolchain {
          inherit name;
          toolset = resolvedToolset;
          policy = resolvedPolicy;
        }
      )
    );

  # ==========================================================================
  # Pre-Built Toolchains
  # ==========================================================================

  toolchains = rec {
    defaultPolicy = mkPolicy { };

    mkStandardToolchain =
      {
        name ? null,
        languages,
        linker,
        bintools,
      }:
      mkToolchain {
        inherit name;
        toolset = mkToolset {
          inherit languages linker bintools;
        };
        policy = defaultPolicy;
      };

    # ========================================================================
    # Clang Toolchains
    # ========================================================================

    # Clang + LLD (Linux default)
    clang-lld = mkStandardToolchain {
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
        mkStandardToolchain {
          languages = {
            c = compilers.clang.c;
            cpp = compilers.clang.cpp;
          };
          linker = linkers.mold;
          bintools = compilers.clang.bintools;
        }
      else
        null;

    # ========================================================================
    # GCC Toolchains
    # ========================================================================
    #
    # Note: GCC only works with GNU ld because it doesn't support the
    # -fuse-ld=/full/path syntax that nixnative uses for alternative linkers.
    # GCC requires just the linker name (e.g., -fuse-ld=lld) which doesn't
    # work reliably with Nix store paths.

    # GCC + GNU ld (the only working GCC combination)
    gcc-ld =
      if gnuLdLinkers.isAvailable && compilers ? gcc && linkers ? ld then
        mkStandardToolchain {
          languages = {
            c = compilers.gcc.c;
            cpp = compilers.gcc.cpp;
          };
          linker = linkers.ld;
          bintools = compilers.gcc.bintools;
        }
      else
        null;

    # ========================================================================
    # Default Toolchain
    # ========================================================================

    # Default toolchain for current platform
    default = clang-lld;
  };

  # ==========================================================================
  # Builder Modules
  # ==========================================================================

  helpers = import ./builders/helpers.nix {
    inherit
      pkgs
      lib
      utils
      language
      ninja
      ;
    inherit (toolCore) processTools;
  };

  # High-level API (Option B style)
  api = import ./builders/api.nix {
    inherit
      pkgs
      lib
      compilers
      linkers
      mkToolchain
      helpers
      ;
  };

  # Project defaults (legacy mkProject)
  projectBuilders = import ./builders/project.nix {
    inherit lib api helpers;
  };

  # Module-first project interface
  projectModules = import ./modules/project.nix {
    inherit lib pkgs api helpers;
  };

  # Installation packaging
  installation = import ./builders/installation.nix {
    inherit pkgs lib;
  };

in
{
  # ==========================================================================
  # Public API
  # ==========================================================================

  # Core factories
  inherit (compilerCore) mkCompiler mkGccStyleScanner validateScanner;
  inherit (linkerCore) mkLinker;
  inherit (toolchainCore)
    validateToolset
    validatePolicy
    validateToolchain
    getCapabilities
    toolchainSupports
    ;

  # Toolset/policy/toolchain factories with project defaults (see let block)
  inherit mkToolset mkPolicy mkToolchain;

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

  # Tool factories (for custom tools)
  inherit (toolCore) mkTool mkGeneratedSources;

  # Test library factory (for custom test frameworks)
  inherit (testLibCore) mkTestLib;

  # Capability presets (for custom linkers)
  linkerCapabilities = {
    inherit (linkerCore)
      lldCapabilities
      moldCapabilities
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
    shell
    test
    ;

  # ==========================================================================
  # Project Helper (recommended for multi-target projects)
  # ==========================================================================
  #
  # Creates scoped builders with shared defaults. Returns an attrset with
  # executable, staticLib, sharedLib, headerOnly, devShell, test functions
  # that automatically merge the project defaults with per-target args.
  #
  # Usage:
  #   let
  #     proj = native.project {
  #       root = ./.;
  #       includeDirs = [ "include" ];
  #       defines = [ "DEBUG" ];
  #     };
  #     libfoo = proj.staticLib { name = "libfoo"; sources = [...]; };
  #     app = proj.executable { name = "app"; libraries = [ libfoo ]; ... };
  #   in { packages = { inherit libfoo app; }; }
  #
  # Targets are real values that can be passed directly to `libraries`,
  # imported from other files, or composed with plain Nix functions.
  #
  inherit (api) project;

  # Module-based project evaluation (alternative API using Nix module system)
  # Use this if you prefer typed options and module composition.
  evalProject = projectModules.evalProject;
  projectModule = projectModules.projectModule;

  # Project defaults - create scoped builders with shared settings (legacy)
  inherit (projectBuilders) mkProject;

  # Installation packaging - create installable packages
  inherit (installation) mkInstallation;

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
  #     toolchain = native.mkToolchain {
  #       toolset = native.mkToolset { languages = ...; linker = ...; bintools = ...; };
  #       policy = native.mkPolicy { };
  #     };
  #     name = "app";
  #     ...
  #   }
  #
  inherit (helpers)
    mkExecutable
    mkStaticLib
    mkSharedLib
    mkHeaderOnly
    ;
  inherit (helpers) mkDevShell mkTest;

  # Tool plugin processing
  inherit (toolCore) processTools;

  # Utilities (for advanced users)
  inherit utils;

  # pkg-config integration
  pkgConfig = pkgConfigUtils;

  # LSP configurations (clangd, etc.)
  inherit lsps;

  # ==========================================================================
  # Flake Output Helpers
  # ==========================================================================
  #
  # Due to Nix dynamic derivations, nixnative packages can't be exposed
  # directly in `packages` (they contain strings from builtins.outputOf,
  # not derivations). Use these helpers for cleaner flake definitions.
  #

  # Extract the actual target from a nixnative package
  # Safe to call on both dynamic and regular derivations
  realizeTarget = pkg:
    if pkg ? passthru && pkg.passthru ? target
    then pkg.passthru.target
    else pkg;

  # Convert a set of nixnative packages to legacyPackages format
  # Usage in flake.nix:
  #   legacyPackages.${system} = native.mkLegacyPackages project.packages;
  mkLegacyPackages = packages:
    lib.mapAttrs (_name: pkg:
      if pkg ? passthru && pkg.passthru ? target
      then pkg.passthru.target
      else pkg
    ) packages;

  # Create a check derivation that builds multiple packages
  # Useful for `nix build .` to build everything
  # Usage:
  #   packages.${system}.default = native.mkBuildAllCheck pkgs "myproject" [
  #     project.packages.foo
  #     project.packages.bar
  #   ];
  mkBuildAllCheck = pkgs': name: packages:
    let
      realizedPkgs = map (pkg:
        if pkg ? passthru && pkg.passthru ? target
        then pkg.passthru.target
        else pkg
      ) packages;
      validInputs = pkg:
        pkg == null
        || lib.isDerivation pkg
        || builtins.isString pkg
        || builtins.isPath pkg;
      filteredPkgs = builtins.filter validInputs realizedPkgs;
    in pkgs'.runCommand "${name}-all-check" {
      buildInputs = filteredPkgs;
    } ''
      mkdir -p $out
      echo "All ${name} components built successfully" > $out/result
    '';

  # ==========================================================================
  # Version Info
  # ==========================================================================

  version = "0.1.0";
  name = "nixnative";
}
