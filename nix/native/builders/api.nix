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
  utils,
  compilers,
  linkers,
  mkToolchain,
  helpers,
}:

let
  compilerNames = builtins.attrNames compilers;
  linkerNames = builtins.attrNames linkers;
  formatNames = names: lib.concatStringsSep ", " names;
  legacyFlagAliases = [
    "cFlags"
    "cxxFlags"
    "ldFlags"
  ];

  assertNoLegacyFlagAliases =
    { context, args }:
    let
      found = builtins.filter (field: args ? ${field}) legacyFlagAliases;
    in
    if found == [ ] then
      null
    else
      throw "nixnative.${context}: unsupported flag fields: ${formatNames found}. Use compileFlags/languageFlags/linkFlags instead.";

  # ==========================================================================
  # Resolvers
  # ==========================================================================

  # Resolve a compiler specification to a compiler family object
  # Accepts: string name ("clang", "gcc") or compiler family object
  # Returns: compiler family with .c, .cpp, .bintools
  resolveCompiler =
    spec:
    let
      available = formatNames compilerNames;
      defaultCompiler = compilers.clang or null;
    in
    if spec == null then
      if defaultCompiler == null then
        throw "Default compiler 'clang' is unavailable. Available: ${available}"
      else
        defaultCompiler
    else if builtins.isString spec then
      let
        resolved = compilers.${spec} or null;
      in
      if resolved == null then
        throw "Unknown or unavailable compiler: '${spec}'. Available: ${available}"
      else
        resolved
    else if builtins.isAttrs spec && spec ? c && spec ? cpp then
      spec # Already a compiler family object
    else
      throw "compiler must be a string name (e.g., \"clang\") or a compiler family object";

  # Resolve a linker specification to a linker object
  # Accepts: string name ("lld", "mold", "ld") or linker object or null
  resolveLinker =
    spec:
    if spec == null then
      null  # Return null to let extractToolchain pick based on compiler
    else if builtins.isString spec then
      let
        resolved = linkers.${spec} or null;
      in
      if resolved == null then
        throw "Unknown or unavailable linker: '${spec}'. Available: ${formatNames linkerNames}"
      else
        resolved
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
        explicitLinker = resolveLinker (args.linker or null);
        # GCC doesn't support -fuse-ld=/full/path, so default to GNU ld for GCC
        # Clang defaults to LLD
        isGcc =
          (args.compiler or null == "gcc")
          || (compilerFamily ? name && lib.hasPrefix "gcc" compilerFamily.name);
        linker =
          if explicitLinker != null then
            explicitLinker
          else if isGcc then
            if linkers ? ld then
              linkers.ld
            else
              throw "GNU ld is required for GCC toolchains but is unavailable on this platform."
          else if linkers ? default then
            linkers.default
          else
            throw "No default linker is available for this platform.";
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
      "scanMode"          # Deprecated, all builds use dynamic mode now
      "dynamic"           # Deprecated alias
    ];

  # ==========================================================================
  # High-Level Builders
  # ==========================================================================

  # Build an executable
  #
  # Arguments:
  #   compiler     - (optional) "clang", "gcc", or compiler family object
  #   linker       - (optional) "lld", "mold", "ld", or linker object
  #   toolchain    - (optional) Pre-built toolchain (overrides compiler/linker)
  #   name         - Target name
  #   root         - Source root directory
  #   sources      - List of source files
  #   includeDirs  - Include directories
  #   defines      - Preprocessor defines
  #   compileFlags - Raw compile flags (all languages)
  #   languageFlags - Per-language raw flags { c = [...]; cpp = [...]; }
  #   linkFlags    - Additional linker flags
  #   libraries    - Library dependencies
  #   tools        - Tool plugins (code generators, etc.)
  #
  executable =
    args:
    let
      _legacyCheck = assertNoLegacyFlagAliases { context = "executable"; inherit args; };
      toolchain = extractToolchain args;
      rootCheck = if !(args ? root) then
        throw "nixnative.executable: 'root' is required. Add 'root = ./.;' to specify your project directory."
      else null;
      cleanedArgs = cleanArgs args;
    in
    builtins.seq _legacyCheck (builtins.seq rootCheck (
      helpers.mkExecutable (cleanedArgs // { inherit toolchain; })
    ));

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
      _legacyCheck = assertNoLegacyFlagAliases { context = "staticLib"; inherit args; };
      toolchain = extractToolchain args;
      rootCheck = if !(args ? root) then
        throw "nixnative.staticLib: 'root' is required. Add 'root = ./.;' to specify your project directory."
      else null;
      cleanedArgs = cleanArgs args;
    in
    builtins.seq _legacyCheck (builtins.seq rootCheck (
      helpers.mkStaticLib (cleanedArgs // { inherit toolchain; })
    ));

  # Build a shared library (.so/.dylib)
  #
  # Arguments same as staticLib, plus:
  #   linkFlags - Additional linker flags
  #
  sharedLib =
    args:
    let
      _legacyCheck = assertNoLegacyFlagAliases { context = "sharedLib"; inherit args; };
      toolchain = extractToolchain args;
      rootCheck = if !(args ? root) then
        throw "nixnative.sharedLib: 'root' is required. Add 'root = ./.;' to specify your project directory."
      else null;
      cleanedArgs = cleanArgs args;
    in
    builtins.seq _legacyCheck (builtins.seq rootCheck (
      helpers.mkSharedLib (cleanedArgs // { inherit toolchain; })
    ));

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

  # Create a standalone development shell (without a target)
  #
  # This is useful when you want a development environment with a specific
  # toolchain but haven't defined any build targets yet.
  #
  # Arguments:
  #   compiler      - (optional) "clang", "gcc", or compiler family object
  #   linker        - (optional) "lld", "mold", "ld", or linker object
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

  # ==========================================================================
  # Project Helper (Scoped Defaults)
  # ==========================================================================
  #
  # Creates a scoped builder with shared defaults. This is the recommended
  # way to define multiple targets with common settings.
  #
  # Usage:
  #   let
  #     proj = native.project {
  #       root = ./.;
  #       includeDirs = [ "include" ];
  #       defines = [ "DEBUG" ];
  #     };
  #
  #     libfoo = proj.staticLib { name = "libfoo"; sources = [ "src/foo.c" ]; };
  #     app = proj.executable { name = "app"; sources = [ "src/main.c" ]; libraries = [ libfoo ]; };
  #   in { packages = { inherit libfoo app; }; }
  #
  # The project function returns scoped builders that merge defaults with
  # per-target arguments. Lists are concatenated, attrs are merged, and
  # scalar values from the target override defaults.
  #
  project =
    defaults:
    let
      _legacyDefaultsCheck = assertNoLegacyFlagAliases { context = "project(defaults)"; args = defaults; };

      isDedupableList = values:
        builtins.all (value: builtins.isString value || builtins.isPath value) values;

      # Fields that should be concatenated (lists)
      listFields = [
        "includeDirs"
        "defines"
        "libraries"
        "tools"
        "publicIncludeDirs"
        "publicDefines"
      ];

      # Fields that should be deeply merged (attrs)
      attrFields = [ ];

      flagSetFrom = attrs: {
        compileFlags = attrs.compileFlags or [ ];
        linkFlags = attrs.linkFlags or [ ];
        languageFlags = attrs.languageFlags or { };
        publicCompileFlags = attrs.publicCompileFlags or [ ];
        publicLinkFlags = attrs.publicLinkFlags or [ ];
      };

      mergeFlagSetForArgs =
        {
          base,
          targetArgs,
          toolchainForMerge,
        }:
        let
          mergeOrder = utils.flagMergeOrderForToolchain toolchainForMerge;
          dedupe = utils.flagDedupeForToolchain toolchainForMerge;
        in
        utils.mergeFlagSets {
          defaults = flagSetFrom base;
          target = flagSetFrom targetArgs;
          inherit mergeOrder dedupe;
        };

      # Merge defaults with target-specific args
      mergeArgs = targetArgs:
        let
          _legacyTargetCheck = assertNoLegacyFlagAliases { context = "project(target)"; args = targetArgs; };

          # Start with defaults
          base = defaults;

          # For list fields: concatenate defaults ++ target
          mergedLists = lib.foldl' (acc: field:
            let
              defaultVal = base.${field} or [];
              targetVal = targetArgs.${field} or [];
              merged = defaultVal ++ targetVal;
              value = if isDedupableList merged then lib.unique merged else merged;
            in
            if defaultVal == [] && targetVal == [] then acc
            else acc // { ${field} = value; }
          ) {} listFields;

          # For attr fields: merge with target taking precedence
          mergedAttrs = lib.foldl' (acc: field:
            let
              defaultVal = base.${field} or {};
              targetVal = targetArgs.${field} or {};
            in
            if defaultVal == {} && targetVal == {} then acc
            else acc // { ${field} = defaultVal // targetVal; }
          ) {} attrFields;

          # Get all other fields from defaults (scalars like root, compiler, etc.)
          scalarDefaults = builtins.removeAttrs base (listFields ++ attrFields);

          # Get all other fields from target args
          scalarTargetArgs = builtins.removeAttrs targetArgs (listFields ++ attrFields);

          mergedScalars = scalarDefaults // scalarTargetArgs;
          mergedFlags = mergeFlagSetForArgs {
            inherit base targetArgs;
            toolchainForMerge = mergedScalars.toolchain or null;
          };
        in
        # Merge order: scalar defaults < scalar target args < merged lists < merged attrs
        builtins.seq _legacyTargetCheck (
          scalarDefaults // scalarTargetArgs // mergedLists // mergedAttrs // mergedFlags
        );

      # Create scoped builders
      scopedExecutable = args: executable (mergeArgs args);
      scopedStaticLib = args: staticLib (mergeArgs args);
      scopedSharedLib = args: sharedLib (mergeArgs args);
      scopedHeaderOnly = args: headerOnly (mergeArgs args);
      scopedDevShell = args: devShell (mergeArgs args);
      scopedTest = args: test (mergeArgs args);
    in
    builtins.seq _legacyDefaultsCheck {
      executable = scopedExecutable;
      staticLib = scopedStaticLib;
      sharedLib = scopedSharedLib;
      headerOnly = scopedHeaderOnly;
      devShell = scopedDevShell;
      test = scopedTest;

      # Expose the defaults for introspection
      inherit defaults;

      # Allow creating a nested project with additional defaults
      extend = extraDefaults: project (mergeArgs extraDefaults);
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
    project
    ;

  # Also expose resolvers for advanced use
  inherit resolveCompiler resolveLinker;
}
