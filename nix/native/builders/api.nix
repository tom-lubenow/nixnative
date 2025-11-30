# High-level API for nixnative
#
# This module provides the primary user-facing API with sensible defaults.
# Users specify `compiler` and `linker` as strings (or objects), and we
# resolve them to a toolchain automatically.
#
# Usage:
#   native.executable { name = "app"; sources = [...]; }
#   native.executable { compiler = "gcc"; linker = "mold"; ... }
#   native.staticLib { compiler = "clang"; ... }
#
# For advanced use cases, pass a pre-built toolchain directly:
#   native.executable { toolchain = myToolchain; ... }
#
{
  lib,
  compilers,
  linkers,
  mkToolchain,
  helpers,
}:

let
  # ==========================================================================
  # Resolvers
  # ==========================================================================

  # Resolve a compiler specification to a compiler family object
  # Accepts: string name ("clang", "gcc") or compiler family object
  # Returns: compiler family with .c, .cpp, .bintools
  resolveCompiler =
    spec:
    if spec == null then
      compilers.clang
    else if builtins.isString spec then
      compilers.${spec} or (throw "Unknown compiler: '${spec}'. Available: clang, gcc")
    else if builtins.isAttrs spec && spec ? c && spec ? cpp then
      spec # Already a compiler family object
    else
      throw "compiler must be a string name (e.g., \"clang\") or a compiler family object";

  # Resolve a linker specification to a linker object
  # Accepts: string name ("lld", "mold", "gold", "ld") or linker object or null
  resolveLinker =
    spec:
    if spec == null then
      linkers.default
    else if builtins.isString spec then
      linkers.${spec} or (throw "Unknown linker: '${spec}'. Available: lld, mold, gold, ld, darwinLd")
    else if builtins.isAttrs spec && spec ? driverFlag then
      spec # Already a linker object
    else
      throw "linker must be a string name (e.g., \"lld\") or a linker object";

  # ==========================================================================
  # Argument Processing
  # ==========================================================================

  # Extract toolchain from args, building one if needed
  # Priority: toolchain > compiler/linker > defaults
  extractToolchain =
    args:
    if args ? toolchain then
      # Toolchain provided directly - could be string or object
      if builtins.isString args.toolchain then
        throw "String toolchain names not supported in high-level API. Use compiler/linker params or pass a toolchain object."
      else
        args.toolchain
    else
      # Build toolchain from compiler/linker
      let
        compilerFamily = resolveCompiler (args.compiler or null);
        linker = resolveLinker (args.linker or null);
      in
      mkToolchain {
        languages = {
          c = compilerFamily.c;
          cpp = compilerFamily.cpp;
        };
        inherit linker;
        bintools = compilerFamily.bintools;
      };

  # Remove our special params from args before passing to mk* functions
  cleanArgs =
    args:
    builtins.removeAttrs args [
      "compiler"
      "linker"
      "toolchain"
    ];

  # ==========================================================================
  # High-Level Builders
  # ==========================================================================

  # Build an executable
  #
  # Arguments:
  #   compiler     - (optional) "clang", "gcc", or compiler family object
  #   linker       - (optional) "lld", "mold", "gold", "ld", or linker object
  #   toolchain    - (optional) Pre-built toolchain (overrides compiler/linker)
  #   name         - Target name
  #   root         - Source root directory
  #   sources      - List of source files
  #   includeDirs  - Include directories
  #   defines      - Preprocessor defines
  #   flags        - Abstract flags (lto, sanitizers, etc.)
  #   compileFlags - Raw compile flags (all languages)
  #   cFlags       - Raw compile flags (C only)
  #   cppFlags     - Raw compile flags (C++ only)
  #   langFlags    - Per-language raw flags { c = [...]; cpp = [...]; }
  #   ldflags      - Additional linker flags
  #   libraries    - Library dependencies
  #   tools        - Tool plugins (protobuf, jinja, etc.)
  #   depsManifest - Pre-computed dependency manifest
  #
  executable =
    args:
    let
      toolchain = extractToolchain args;
      cleanedArgs = cleanArgs args;
    in
    helpers.mkExecutable (cleanedArgs // { inherit toolchain; });

  # Build a static library (.a)
  #
  # Additional arguments (in addition to executable args):
  #   compileFlags      - Raw compile flags (all languages)
  #   cFlags            - Raw compile flags (C only)
  #   cppFlags          - Raw compile flags (C++ only)
  #   langFlags         - Per-language raw flags { c = [...]; cpp = [...]; }
  #   publicIncludeDirs - Headers to expose to consumers
  #   publicDefines     - Defines to propagate to consumers
  #   publicCxxFlags    - C++ flags to propagate to consumers
  #
  staticLib =
    args:
    let
      toolchain = extractToolchain args;
      cleanedArgs = cleanArgs args;
    in
    helpers.mkStaticLib (cleanedArgs // { inherit toolchain; });

  # Build a shared library (.so/.dylib)
  #
  # Arguments same as staticLib, plus:
  #   ldflags - Additional linker flags
  #
  sharedLib =
    args:
    let
      toolchain = extractToolchain args;
      cleanedArgs = cleanArgs args;
    in
    helpers.mkSharedLib (cleanedArgs // { inherit toolchain; });

  # Create a header-only library (no compilation)
  #
  # Note: Header-only libraries don't need a toolchain, so we just pass through
  headerOnly = helpers.mkHeaderOnly;

  # Create a development shell
  #
  # Arguments:
  #   target          - A built target (executable, library)
  #   compiler        - (optional) Override compiler for shell
  #   linker          - (optional) Override linker for shell
  #   toolchain       - (optional) Override toolchain for shell
  #   extraPackages   - Additional packages to include
  #   linkCompileCommands - Whether to symlink compile_commands.json
  #
  devShell =
    args:
    let
      # For devShell, toolchain is optional - can come from target
      toolchain =
        if args ? toolchain || args ? compiler || args ? linker then extractToolchain args else null; # Let mkDevShell extract from target
      cleanedArgs = cleanArgs args;
    in
    helpers.mkDevShell (cleanedArgs // (if toolchain != null then { inherit toolchain; } else { }));

  # Create a test runner
  test = helpers.mkTest;

  # Create a static archive (.a) from a static library
  #
  # Use when you need an actual archive file for external distribution
  # or traditional archive link semantics.
  #
  archive = helpers.mkArchive;

in
{
  inherit
    executable
    staticLib
    sharedLib
    headerOnly
    devShell
    test
    archive
    ;

  # Also expose resolvers for advanced use
  inherit resolveCompiler resolveLinker;
}
