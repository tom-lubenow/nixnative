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
# Dynamic Derivations:
#   nixnative uses Nix dynamic derivations (RFC 92) for incremental builds.
#   This eliminates IFD (Import From Derivation) during evaluation while
#   enabling per-file incremental compilation at build time.
#
#   Requirements:
#     experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
#
#
{
  pkgs,
  lib,
  compilers,
  linkers,
  mkToolchain,
  helpers,
  flags,
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
  # Accepts: string name ("lld", "mold", "ld") or linker object or null
  # Note: gold support removed (deprecated upstream)
  resolveLinker =
    spec:
    if spec == null then
      null  # Return null to let extractToolchain pick based on compiler
    else if builtins.isString spec then
      linkers.${spec} or (throw "Unknown linker: '${spec}'. Available: lld, mold, ld")
    else if builtins.isAttrs spec && spec ? driverFlag then
      spec # Already a linker object
    else
      throw "linker must be a string name (e.g., \"lld\") or a linker object";

  # ==========================================================================
  # Argument Processing
  # ==========================================================================

  # Extract toolchain from args, building one if needed
  # Priority: toolchain > compiler/linker > defaults
  # Also handles contentAddressed - passes to toolchain if building one
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
        explicitLinker = resolveLinker (args.linker or null);
        # GCC doesn't support -fuse-ld=/full/path, so default to GNU ld for GCC
        # Clang defaults to LLD
        isGcc = args.compiler or null == "gcc";
        linker = if explicitLinker != null then explicitLinker
                 else if isGcc then linkers.ld
                 else linkers.default;
        contentAddressed = args.contentAddressed or false;
      in
      mkToolchain {
        languages = {
          c = compilerFamily.c;
          cpp = compilerFamily.cpp;
        };
        inherit linker contentAddressed;
        bintools = compilerFamily.bintools;
      };

  # Extract abstract flags from ergonomic parameters
  # Converts: { lto = "thin"; sanitizers = ["address"]; } -> [ flags.lto "thin", flags.sanitizer "address" ]
  extractFlags =
    args:
    let
      # Get explicit flags list if provided
      explicitFlags = args.flags or [];
      # Convert ergonomic params to abstract flags
      ergonomicFlags = flags.fromArgs args;
    in
    explicitFlags ++ ergonomicFlags;

  # Remove our special params from args before passing to mk* functions
  cleanArgs =
    args:
    builtins.removeAttrs args [
      "compiler"
      "linker"
      "toolchain"
      "contentAddressed"  # Handled by extractToolchain, stored in toolchain
      "scanMode"          # Deprecated, all builds use dynamic mode now
      "dynamic"           # Deprecated alias
      # Ergonomic flag params (converted to flags list)
      "lto"
      "sanitizers"
      "coverage"
      "optimize"
      "debug"
      "standard"
      "warnings"
      "pic"
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
  #   langFlags    - Per-language raw flags { c = [...]; cpp = [...]; }
  #   ldflags      - Additional linker flags
  #   libraries    - Library dependencies
  #   tools        - Tool plugins (code generators, etc.)
  #
  # Ergonomic flag parameters (alternative to flags list):
  #   lto          - LTO mode: "thin", "full", or true (defaults to thin)
  #   sanitizers   - List of sanitizers: ["address", "undefined", ...]
  #   coverage     - Enable coverage instrumentation: true/false
  #   optimize     - Optimization level: "0", "1", "2", "3", "s", "z", "fast"
  #   debug        - Debug info: "none", "line-tables", "full"
  #   standard     - Language standard: "c++17", "c++20", "c11", etc.
  #   warnings     - Warning level: "none", "default", "all", "extra", "pedantic"
  #   pic          - Position independent code: true/false
  #
  executable =
    args:
    let
      toolchain = extractToolchain args;
      abstractFlags = extractFlags args;
      cleanedArgs = cleanArgs args;
      # Validate root is provided with helpful error
      _ = if !(args ? root) then
        throw "nixnative.executable: 'root' is required. Add 'root = ./.;' to specify your project directory."
      else null;
    in
    helpers.mkExecutable (cleanedArgs // { inherit toolchain; flags = abstractFlags; });

  # Build a static library (.a)
  #
  # Additional arguments (in addition to executable args):
  #   publicIncludeDirs - Headers to expose to consumers
  #   publicDefines     - Defines to propagate to consumers
  #   publicCxxFlags    - C++ flags to propagate to consumers
  #
  staticLib =
    args:
    let
      toolchain = extractToolchain args;
      abstractFlags = extractFlags args;
      cleanedArgs = cleanArgs args;
      # Validate root is provided with helpful error
      _ = if !(args ? root) then
        throw "nixnative.staticLib: 'root' is required. Add 'root = ./.;' to specify your project directory."
      else null;
    in
    helpers.mkStaticLib (cleanedArgs // { inherit toolchain; flags = abstractFlags; });

  # Build a shared library (.so/.dylib)
  #
  # Arguments same as staticLib, plus:
  #   ldflags - Additional linker flags
  #
  sharedLib =
    args:
    let
      toolchain = extractToolchain args;
      abstractFlags = extractFlags args;
      cleanedArgs = cleanArgs args;
      # Validate root is provided with helpful error
      _ = if !(args ? root) then
        throw "nixnative.sharedLib: 'root' is required. Add 'root = ./.;' to specify your project directory."
      else null;
    in
    helpers.mkSharedLib (cleanedArgs // { inherit toolchain; flags = abstractFlags; });

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

  # Create a standalone development shell (without a target)
  #
  # This is useful when you want a development environment with a specific
  # toolchain but haven't defined any build targets yet.
  #
  # Arguments:
  #   compiler      - (optional) "clang", "gcc", or compiler family object
  #   linker        - (optional) "lld", "mold", "gold", "ld", or linker object
  #   toolchain     - (optional) Pre-built toolchain (overrides compiler/linker)
  #   extraPackages - Additional packages to include in the shell
  #   includeTools  - Whether to include clang-tools and gdb (default: true)
  #
  # Example:
  #   native.shell { compiler = "clang"; linker = "mold"; }
  #   native.shell { extraPackages = [ pkgs.cmake pkgs.ninja ]; }
  #
  shell =
    args:
    let
      toolchain = extractToolchain args;
      extraPackages = args.extraPackages or [];
      includeTools = args.includeTools or true;

      # Include common development tools
      devTools =
        if includeTools then
          [
            pkgs.clang-tools
            pkgs.gdb
          ]
        else
          [];

      packages = lib.unique (
        toolchain.runtimeInputs
        ++ devTools
        ++ extraPackages
      );

      # Environment exports
      envExports = toolchain.getEnvironmentExports;
    in
    pkgs.mkShell {
      inherit packages;
      shellHook = ''
        export CC="${toolchain.getCompilerForLanguage "c"}"
        export CXX="${toolchain.getCompilerForLanguage "cpp"}"
        ${envExports}
      '';
    };

in
{
  inherit
    executable
    staticLib
    sharedLib
    headerOnly
    devShell
    shell
    test
    archive
    ;

  # Also expose resolvers for advanced use
  inherit resolveCompiler resolveLinker;
}
