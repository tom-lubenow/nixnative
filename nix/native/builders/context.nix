# Build context for nixnative
#
# A build context aggregates all configuration needed to compile a target:
# sources, include directories, defines, flags, libraries, tools, etc.
#
{
  pkgs,
  lib,
  utils,
  flags,
  compile,
  scanner,
}:

let
  inherit (lib) concatStringsSep;
  inherit (utils)
    sanitizePath
    emptyPublic
    mergePublic
    collectPublic
    collectEvalInputs
    normalizeSources
    headerSet
    validatePublic
    ;
  inherit (scanner)
    mkManifest
    emptyManifest
    mergeManifests
    processTools
    mkDependencyScanner
    ;
  inherit (compile)
    compileTranslationUnit
    generateCompileCommands
    ;

in
rec {
  # ==========================================================================
  # Build Context Factory
  # ==========================================================================

  # Create a build context that aggregates all compilation settings
  #
  # Arguments:
  #   name         - Target name
  #   toolchain    - Toolchain from mkToolchain
  #   root         - Source root directory
  #   sources      - List of source files
  #   includeDirs  - Include directories
  #   defines      - Preprocessor defines
  #   flags        - Abstract flags (lto, sanitizers, etc.)
  #   compileFlags - Raw compile-only flags (all languages)
  #   langFlags    - Per-language raw flags { c = [...]; cpp = [...]; }
  #   libraries    - Library dependencies
  #   tools        - Tool plugins (protobuf, jinja, etc.)
  #   depsManifest - Pre-computed dependency manifest
  #   scanner      - Custom scanner (if not using auto-scan)
  #
  mkBuildContext =
    {
      name,
      toolchain,
      root,
      sources,
      includeDirs ? [ ],
      defines ? [ ],
      flags ? [ ], # Abstract flags from flags.nix
      compileFlags ? [ ], # Raw compile-only flags (all languages)
      langFlags ? { }, # Per-language raw flags
      libraries ? [ ],
      tools ? [ ], # Tool plugins (replaces generators)
      depsManifest ? null,
      scanner ? null,
      ...
    }@args:
    let
      tc = toolchain;
      rootPath = sanitizePath { path = root; };

      # Process tool plugins
      toolInfo = processTools tools;

      # Validate public attributes from libraries
      _ = map (
        lib:
        if lib ? public then
          validatePublic {
            public = lib.public;
            context = "library '${lib.name or "unknown"}'";
          }
        else
          true
      ) libraries;

      # Collect public attributes from libraries
      libsPublic = collectPublic libraries;

      # Collect evalInputs from libraries (packages needed in sandbox for headers)
      libsEvalInputs = collectEvalInputs libraries;

      # Merge library and tool public attributes
      publicAggregate = mergePublic libsPublic toolInfo.public;

      # Combine sources (user sources + tool-generated sources)
      allSources = sources ++ toolInfo.sources;

      # Combine include directories
      combinedIncludeDirs = includeDirs ++ publicAggregate.includeDirs ++ toolInfo.includeDirs;

      # Combine defines
      combinedDefines = defines ++ publicAggregate.defines ++ toolInfo.defines;

      # Combine compile-only flags (all languages)
      combinedCompileFlags = compileFlags ++ publicAggregate.cxxFlags ++ toolInfo.cxxFlags;

      # Per-language compile flags (merge user langFlags with tool/lib cxxFlags into cpp)
      combinedLangFlags = langFlags;

      # Normalize sources to translation units
      tus = normalizeSources {
        inherit root;
        sources = allSources;
      };

      # Auto-create scanner if needed
      autoScanner =
        if depsManifest == null && scanner == null then
          mkDependencyScanner {
            name = "${name}-scanner";
            inherit root;
            sources = allSources;
            includeDirs = combinedIncludeDirs;
            defines = combinedDefines;
            extraFlags = combinedCompileFlags;
            libraries = libraries;
            tools = tools;
            toolchain = tc;
          }
        else
          null;

      effectiveScanner = if scanner != null then scanner else autoScanner;

      # Build dependency manifest
      baseManifest =
        if depsManifest != null then
          mkManifest depsManifest
        else if effectiveScanner != null then
          mkManifest effectiveScanner
        else
          emptyManifest;

      manifest = mergeManifests baseManifest toolInfo.manifest;

      # Compile all translation units
      objectInfos = map (
        tu:
        let
          headers = headerSet {
            inherit root manifest tu;
            overrides = toolInfo.headerOverrides;
          };
        in
        compileTranslationUnit {
          inherit root tu headers;
          toolchain = tc;
          includeDirs = combinedIncludeDirs;
          defines = combinedDefines;
          inherit flags;
          compileFlags = combinedCompileFlags;
          langFlags = combinedLangFlags;
          extraInputs = toolInfo.evalInputs ++ libsEvalInputs;
        }
      ) tus;

      # Extract object paths for linking
      objectPaths = map (info: info.object) objectInfos;

      # Generate compile_commands.json
      compileCommands = generateCompileCommands {
        toolchain = tc;
        root = rootPath;
        inherit tus;
        includeDirs = combinedIncludeDirs;
        defines = combinedDefines;
        inherit flags;
        compileFlags = combinedCompileFlags;
        langFlags = combinedLangFlags;
      };

    in
    {
      inherit name toolchain rootPath;
      inherit objectInfos objectPaths compileCommands;
      inherit manifest tus;
      inherit combinedIncludeDirs combinedDefines;
      inherit combinedCompileFlags combinedLangFlags;
      inherit publicAggregate;
      inherit libraries tools;
      inherit flags;
      inherit libsEvalInputs;
      scanner = effectiveScanner;
    };
}
