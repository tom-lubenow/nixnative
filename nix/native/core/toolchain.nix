# Toolchain abstraction for nixnative
#
# A toolchain composes language compilers, a linker, and binutils into a
# complete build environment. Languages are explicitly specified via a map.
#
# Usage:
#   mkToolchain {
#     languages = {
#       c = native.compilers.clang.c;
#       cpp = native.compilers.clang.cpp;
#       rust = native.compilers.rustc.rust;
#     };
#     linker = native.linkers.lld;
#     bintools = native.compilers.clang.bintools;
#   }
#
# Content-Addressed Derivations:
# ------------------------------
# When contentAddressed = true, the toolchain configures scanner (and
# potentially other) derivations to use Nix's content-addressed mode.
# This enables better incrementality: identical outputs are deduplicated
# even when inputs differ.
#
# Note: Requires Nix with the 'ca-derivations' experimental feature enabled.
#
{
  lib,
  platform,
  language,
}:

rec {
  # ==========================================================================
  # Toolchain Factory
  # ==========================================================================

  mkToolchain =
    {
      name ? null, # Optional name (auto-generated if not provided)
      languages, # Map of language name -> language config
      linker, # Linker object from mkLinker
      bintools ? { }, # Bintools (ar, ranlib, nm, etc.)

      # Platform configuration
      targetPlatform, # The platform we're building for

      # Additional inputs and environment
      runtimeInputs ? [ ], # Additional packages for PATH
      environment ? { }, # Additional environment variables

      # Content-addressed derivations (experimental)
      # When true, scanner derivations use CA mode for better incrementality
      contentAddressed ? false,
    }:
    let
      # Generate name from languages if not provided
      generatedName =
        let
          langNames = builtins.attrNames languages;
          firstLang = builtins.head langNames;
          compilerName = languages.${firstLang}.name or "unknown";
        in
        "${compilerName}-${linker.name}";

      finalName = if name != null then name else generatedName;

      # Collect runtime inputs from all language compilers
      languageRuntimeInputs = lib.flatten (
        lib.mapAttrsToList (_: lang: lang.runtimeInputs or [ ]) languages
      );

      # Merge runtime inputs from all sources
      allRuntimeInputs =
        languageRuntimeInputs
        ++ (linker.runtimeInputs or [ ])
        ++ runtimeInputs;

      # Merge environments from all language compilers
      languageEnvironments = lib.foldl' (acc: lang: acc // (lang.environment or { })) { } (
        builtins.attrValues languages
      );

      finalEnvironment =
        languageEnvironments
        // (linker.environment or { })
        // environment;

      # Extract cxxRuntimeLibPath from cpp language if present
      cxxRuntimeLibPath =
        if languages ? cpp then
          languages.cpp.cxxRuntimeLibPath or null
        else
          null;
    in
    {
      name = finalName;
      inherit
        languages
        linker
        bintools
        targetPlatform
        contentAddressed
        ;

      # Bintools accessors (for convenience)
      ar = bintools.ar or null;
      ranlib = bintools.ranlib or null;
      nm = bintools.nm or null;
      objcopy = bintools.objcopy or null;
      strip = bintools.strip or null;

      runtimeInputs = allRuntimeInputs;
      environment = finalEnvironment;

      inherit cxxRuntimeLibPath;

      # =======================================================================
      # Language-Aware Methods
      # =======================================================================

      # Get the compiler command for a language
      getCompilerForLanguage = lang:
        if languages ? ${lang} then
          languages.${lang}.compiler
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}'";

      # Get default flags for a language
      getDefaultFlagsForLanguage = lang:
        if languages ? ${lang} then
          languages.${lang}.defaultFlags
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}'";

      # Check if toolchain supports a language
      supportsLanguage = lang: languages ? ${lang};

      # Detect language name from filename
      getLanguageNameForFile = filename:
        language.detectLanguageName filename;

      # Detect language from filename and get compiler
      getCompilerForFile = filename:
        let lang = language.detectLanguageName filename;
        in
        if languages ? ${lang} then
          languages.${lang}.compiler
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}' (detected from '${filename}')";

      # Detect language from filename and get default flags
      getDefaultFlagsForFile = filename:
        let lang = language.detectLanguageName filename;
        in
        if languages ? ${lang} then
          languages.${lang}.defaultFlags
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}' (detected from '${filename}')";

      # Get the full language config for a file
      getLanguageConfigForFile = filename:
        let lang = language.detectLanguageName filename;
        in
        if languages ? ${lang} then
          languages.${lang}
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}' (detected from '${filename}')";

      # =======================================================================
      # Convenience Accessors
      # =======================================================================

      # Check if specific languages are available
      hasC = languages ? c;
      hasCpp = languages ? cpp;
      hasRust = languages ? rust;

      # Get language configs (throws if not present)
      getCConfig =
        if languages ? c then languages.c
        else throw "nixnative: toolchain '${finalName}' does not have C support";

      getCppConfig =
        if languages ? cpp then languages.cpp
        else throw "nixnative: toolchain '${finalName}' does not have C++ support";

      getRustConfig =
        if languages ? rust then languages.rust
        else throw "nixnative: toolchain '${finalName}' does not have Rust support";

      # =======================================================================
      # Linker Methods
      # =======================================================================

      # Get linker driver flag for compiler
      getLinkerFlag = linker.driverFlag;

      # Check if linker supports a capability
      linkerHas = cap: linker.hasCapability cap;

      # Wrap library flags for linking (handles --start-group on Linux)
      wrapLibraryFlags =
        libs:
        linker.wrapLinkFlags {
          platform = targetPlatform;
          flags = libs;
        };

      # Get platform-specific linker flags
      getPlatformLinkerFlags = linker.platformFlags targetPlatform;

      # =======================================================================
      # Environment
      # =======================================================================

      # Build environment variables as shell export string
      getEnvironmentExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") finalEnvironment
      );

      # Get all platform-specific compile flags (e.g., -fPIC on Linux)
      getPlatformCompileFlags = platform.defaultCompileFlags targetPlatform;
    };

  # ==========================================================================
  # Toolchain Validation
  # ==========================================================================

  validateToolchain =
    toolchain:
    let
      required = [
        "name"
        "languages"
        "linker"
        "targetPlatform"
      ];
      missing = builtins.filter (f: !(toolchain ? ${f})) required;
    in
    if missing != [ ] then
      throw "nixnative: toolchain missing required fields: ${lib.concatStringsSep ", " missing}"
    else if toolchain.languages == { } then
      throw "nixnative: toolchain must have at least one language"
    else if !(toolchain.linker ? driverFlag) then
      throw "nixnative: toolchain linker is missing 'driverFlag' field"
    else
      toolchain;

  # ==========================================================================
  # Capability Queries
  # ==========================================================================

  # Get all capabilities supported by the toolchain
  getCapabilities =
    toolchain:
    let
      # Get capabilities from first C/C++ language
      langCaps =
        if toolchain.languages ? cpp then toolchain.languages.cpp.capabilities or { }
        else if toolchain.languages ? c then toolchain.languages.c.capabilities or { }
        else { };
      linkerCaps = toolchain.linker.capabilities or { };
    in
    {
      # LTO requires both compiler and linker support
      lto =
        if langCaps.lto or null == null then
          null
        else if !(linkerCaps.lto or false) then
          null
        else
          langCaps.lto;

      thinLto = (langCaps.lto.thin or false) && (linkerCaps.thinLto or false);

      # Sanitizers come from compiler
      sanitizers = langCaps.sanitizers or [ ];

      # Coverage comes from compiler
      coverage = langCaps.coverage or false;

      # ICF comes from linker
      icf = linkerCaps.icf or false;

      # Parallel linking from linker
      parallelLinking = linkerCaps.parallelLinking or false;

      # Split DWARF requires both
      splitDwarf = (langCaps.splitDwarf or false) && (linkerCaps.splitDwarf or false);

      # Color diagnostics from compiler
      colorDiagnostics = langCaps.colorDiagnostics or false;

      # C++20 modules from compiler
      modules = langCaps.modules or false;

      # PCH from compiler
      pch = langCaps.pch or false;
    };

  # Check if a specific feature is supported by the toolchain
  toolchainSupports =
    toolchain: feature:
    let
      caps = getCapabilities toolchain;
    in
    if feature == "lto" then
      caps.lto != null
    else if feature == "thinLto" then
      caps.thinLto
    else if feature == "sanitizers" then
      caps.sanitizers != [ ]
    else
      caps.${feature} or false;
}
