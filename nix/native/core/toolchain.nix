# Toolchain abstraction for nixnative
#
# A toolchain composes a compiler, linker, and binutils into a complete
# build environment. It supports multiple languages, with each language
# having its own compiler binary and default flags.
#
{
  lib,
  flags,
  platform,
  language,
}:

rec {
  # ==========================================================================
  # Toolchain Factory
  # ==========================================================================

  mkToolchain =
    {
      name, # Identifier: "clang18-lld", "gcc14-mold"
      compiler, # Compiler object from mkCompiler
      linker, # Linker object from mkLinker

      # Binutils
      ar, # Path to archiver (ar)
      ranlib ? null, # Path to ranlib (optional, some use ar -s)
      nm ? null, # Path to nm
      objcopy ? null, # Path to objcopy
      strip ? null, # Path to strip

      # Platform configuration
      targetPlatform, # The platform we're building for

      # Additional inputs and environment
      runtimeInputs ? [ ], # Additional packages for PATH
      environment ? { }, # Additional environment variables
    }:
    let
      # Merge runtime inputs from compiler, linker, and toolchain
      allRuntimeInputs =
        (compiler.runtimeInputs or [ ]) ++ (linker.runtimeInputs or [ ]) ++ runtimeInputs;

      # Merge environments (toolchain overrides linker overrides compiler)
      finalEnvironment = (compiler.environment or { }) // (linker.environment or { }) // environment;

      # Build the languages map from the compiler object
      # This maps language names to their compilation settings
      languages = {
        c = {
          compiler = compiler.cc;
          defaultFlags = compiler.defaultCFlags or [ ];
        };
        cpp = {
          compiler = compiler.cxx;
          defaultFlags = compiler.defaultCxxFlags or [ ];
        };
        # Future: additional languages can be added via optional compiler fields
        # e.g., objc, objcpp, or even external compilers like rustc
      };
    in
    {
      inherit
        name
        compiler
        linker
        targetPlatform
        languages
        ;
      inherit
        ar
        ranlib
        nm
        objcopy
        strip
        ;

      runtimeInputs = allRuntimeInputs;
      environment = finalEnvironment;

      # =======================================================================
      # Language-Aware Methods
      # =======================================================================

      # Get the compiler command for a language
      getCompilerForLanguage = lang:
        if languages ? ${lang} then
          languages.${lang}.compiler
        else
          throw "nixnative: toolchain '${name}' does not support language '${lang}'";

      # Get default flags for a language
      getDefaultFlagsForLanguage = lang:
        if languages ? ${lang} then
          languages.${lang}.defaultFlags
        else
          throw "nixnative: toolchain '${name}' does not support language '${lang}'";

      # Check if toolchain supports a language
      supportsLanguage = lang: languages ? ${lang};

      # Detect language from filename and get compiler
      getCompilerForFile = filename:
        let lang = language.detectLanguageName filename;
        in languages.${lang}.compiler;

      # Detect language from filename and get default flags
      getDefaultFlagsForFile = filename:
        let lang = language.detectLanguageName filename;
        in languages.${lang}.defaultFlags;

      # =======================================================================
      # Legacy Methods (for compatibility during transition)
      # =======================================================================

      # Get the C compiler command
      getCC = languages.c.compiler;

      # Get the C++ compiler command
      getCXX = languages.cpp.compiler;

      # Get C++ runtime library path (for rpath on Linux)
      cxxRuntimeLibPath = compiler.cxxRuntimeLibPath or null;

      # Get linker driver flag for compiler
      getLinkerFlag = linker.driverFlag;

      # Translate abstract flags to concrete CLI args
      translateFlags = flagList: compiler.translateFlags flagList;

      # Check if compiler supports a capability
      compilerHas = cap: compiler.hasCapability cap;

      # Check if linker supports a capability
      linkerHas = cap: linker.hasCapability cap;

      # Check if both compiler and linker support LTO
      supportsLTO = compiler.hasCapability "lto" && linker.hasCapability "lto";

      # Check if toolchain supports thin LTO specifically
      supportsThinLTO =
        let
          compilerLTO = compiler.capabilities.lto or null;
          linkerThinLTO = linker.capabilities.thinLto or false;
        in
        compilerLTO != null && (compilerLTO.thin or false) && linkerThinLTO;

      # Wrap library flags for linking (handles --start-group on Linux)
      wrapLibraryFlags =
        libs:
        linker.wrapLinkFlags {
          platform = targetPlatform;
          flags = libs;
        };

      # Get platform-specific linker flags
      getPlatformLinkerFlags = linker.platformFlags targetPlatform;

      # Get all default C flags
      getDefaultCFlags = languages.c.defaultFlags;

      # Get all default C++ flags
      getDefaultCxxFlags = languages.cpp.defaultFlags;

      # Build environment variables as shell export string
      getEnvironmentExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") finalEnvironment
      );

      # Get all platform-specific compile flags (e.g., -fPIC on Linux)
      getPlatformCompileFlags = platform.defaultCompileFlags targetPlatform;
    };

  # ==========================================================================
  # Toolchain Composition Helpers
  # ==========================================================================

  # Create a toolchain name from compiler and linker
  makeToolchainName = compiler: linker: "${compiler.name}-${linker.name}";

  # Validate that compiler and linker are compatible
  validateToolchain =
    toolchain:
    let
      required = [
        "name"
        "compiler"
        "linker"
        "ar"
        "targetPlatform"
      ];
      missing = builtins.filter (f: !(toolchain ? ${f})) required;
    in
    if missing != [ ] then
      throw "nixnative: toolchain missing required fields: ${lib.concatStringsSep ", " missing}"
    else if !(toolchain.compiler ? cc) then
      throw "nixnative: toolchain compiler is missing 'cc' field"
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
      compilerCaps = toolchain.compiler.capabilities or { };
      linkerCaps = toolchain.linker.capabilities or { };
    in
    {
      # LTO requires both compiler and linker support
      lto =
        if compilerCaps.lto or null == null then
          null
        else if !(linkerCaps.lto or false) then
          null
        else
          compilerCaps.lto;

      thinLto = (compilerCaps.lto.thin or false) && (linkerCaps.thinLto or false);

      # Sanitizers come from compiler
      sanitizers = compilerCaps.sanitizers or [ ];

      # Coverage comes from compiler
      coverage = compilerCaps.coverage or false;

      # ICF comes from linker
      icf = linkerCaps.icf or false;

      # Parallel linking from linker
      parallelLinking = linkerCaps.parallelLinking or false;

      # Split DWARF requires both
      splitDwarf = (compilerCaps.splitDwarf or false) && (linkerCaps.splitDwarf or false);

      # Color diagnostics from compiler
      colorDiagnostics = compilerCaps.colorDiagnostics or false;

      # C++20 modules from compiler
      modules = compilerCaps.modules or false;

      # PCH from compiler
      pch = compilerCaps.pch or false;
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
