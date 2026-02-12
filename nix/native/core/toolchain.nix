# Toolchain abstraction for nixnative
#
# A toolchain is the composition of:
#   - toolset: compilers, linker, and bintools
#   - policy: platform and build-environment conventions
#
# This split keeps tool definitions (what to run) separate from policy
# (how to run in a given environment).
#
# Usage:
#   toolset = mkToolset {
#     languages = {
#       c = native.compilers.clang.c;
#       cpp = native.compilers.clang.cpp;
#     };
#     linker = native.linkers.lld;
#     bintools = native.compilers.clang.bintools;
#   };
#
#   policy = mkPolicy {
#     targetPlatform = pkgs.stdenv.targetPlatform;
#   };
#
#   tc = mkToolchain {
#     inherit toolset policy;
#   };
#
{
  lib,
  platform,
  language,
}:

rec {
  # ==========================================================================
  # Toolset Factory
  # ==========================================================================

  mkToolset =
    {
      name ? null,
      languages,
      linker,
      bintools ? { },
      runtimeInputs ? [ ],
      environment ? { },
    }:
    let
      generatedName =
        let
          langKey =
            if languages ? cpp then "cpp"
            else if languages ? c then "c"
            else builtins.head (builtins.attrNames languages);
          compilerName = languages.${langKey}.name or "unknown";
        in
        "${compilerName}-${linker.name}";

      finalName = if name != null then name else generatedName;

      languageRuntimeInputs = lib.flatten (
        lib.mapAttrsToList (_: lang: lang.runtimeInputs or [ ]) languages
      );

      allRuntimeInputs =
        lib.unique (
          languageRuntimeInputs
          ++ (linker.runtimeInputs or [ ])
          ++ runtimeInputs
        );

      languageEnvironments = lib.foldl' (acc: lang: acc // (lang.environment or { })) { } (
        builtins.attrValues languages
      );

      finalEnvironment =
        languageEnvironments
        // (linker.environment or { })
        // environment;
    in
    validateToolset {
      kind = "toolset";
      name = finalName;
      inherit
        languages
        linker
        bintools
        ;
      runtimeInputs = allRuntimeInputs;
      environment = finalEnvironment;
    };

  # ==========================================================================
  # Policy Factory
  # ==========================================================================

  mkPolicy =
    {
      name ? "default",
      targetPlatform,
      runtimeInputs ? [ ],
      environment ? { },
      flags ? { },
    }:
    let
      finalFlags = {
        mergeOrder = "defaults-first";
        dedupeStringPathLists = true;
      } // flags;
    in
    validatePolicy {
      kind = "policy";
      inherit
        name
        targetPlatform
        runtimeInputs
        environment
        ;
      flags = finalFlags;
    };

  # ==========================================================================
  # Toolchain Factory
  # ==========================================================================

  mkToolchain =
    {
      name ? null,
      toolset,
      policy,
    }:
    let
      finalToolset = validateToolset toolset;
      finalPolicy = validatePolicy policy;

      generatedName =
        if finalPolicy.name == "default" then
          finalToolset.name
        else
          "${finalToolset.name}-${finalPolicy.name}";

      finalName = if name != null then name else generatedName;

      languages = finalToolset.languages;
      linker = finalToolset.linker;
      bintools = finalToolset.bintools;
      targetPlatform = finalPolicy.targetPlatform;

      allRuntimeInputs = lib.unique (finalToolset.runtimeInputs ++ finalPolicy.runtimeInputs);
      finalEnvironment = finalToolset.environment // finalPolicy.environment;

      cxxRuntimeLibPath =
        if languages ? cpp then
          languages.cpp.cxxRuntimeLibPath or null
        else
          null;
    in
    {
      name = finalName;
      kind = "toolchain";

      inherit toolset policy;

      # Compatibility/convenience accessors
      inherit
        languages
        linker
        bintools
        targetPlatform
        ;

      # Bintools accessors
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

      getCompilerForLanguage = lang:
        if languages ? ${lang} then
          languages.${lang}.compiler
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}'";

      getDefaultFlagsForLanguage = lang:
        if languages ? ${lang} then
          languages.${lang}.defaultFlags
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}'";

      supportsLanguage = lang: languages ? ${lang};

      getLanguageNameForFile = filename:
        language.detectLanguageName filename;

      getCompilerForFile = filename:
        let lang = language.detectLanguageName filename;
        in
        if languages ? ${lang} then
          languages.${lang}.compiler
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}' (detected from '${filename}')";

      getDefaultFlagsForFile = filename:
        let lang = language.detectLanguageName filename;
        in
        if languages ? ${lang} then
          languages.${lang}.defaultFlags
        else
          throw "nixnative: toolchain '${finalName}' does not support language '${lang}' (detected from '${filename}')";

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

      hasC = languages ? c;
      hasCpp = languages ? cpp;
      hasRust = languages ? rust;

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

      getLinkerFlag = linker.driverFlag;
      linkerHas = cap: linker.hasCapability cap;

      wrapLibraryFlags =
        libs:
        linker.wrapLinkFlags {
          platform = targetPlatform;
          flags = libs;
        };

      getPlatformLinkerFlags = linker.platformFlags targetPlatform;

      # =======================================================================
      # Policy
      # =======================================================================

      getFlagPolicy = finalPolicy.flags;

      # =======================================================================
      # Environment
      # =======================================================================

      getEnvironmentExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") finalEnvironment
      );

      getPlatformCompileFlags = platform.defaultCompileFlags targetPlatform;
    };

  # ==========================================================================
  # Validation
  # ==========================================================================

  validateToolset =
    toolset:
    let
      required = [
        "name"
        "languages"
        "linker"
      ];
      missing = builtins.filter (f: !(toolset ? ${f})) required;
    in
    if missing != [ ] then
      throw "nixnative: toolset missing required fields: ${lib.concatStringsSep ", " missing}"
    else if toolset.languages == { } then
      throw "nixnative: toolset must have at least one language"
    else if !(toolset.linker ? driverFlag) then
      throw "nixnative: toolset linker is missing 'driverFlag' field"
    else
      toolset;

  validatePolicy =
    policy:
    let
      required = [
        "name"
        "targetPlatform"
        "runtimeInputs"
        "environment"
        "flags"
      ];
      missing = builtins.filter (f: !(policy ? ${f})) required;
      mergeOrder = policy.flags.mergeOrder or "defaults-first";
    in
    if missing != [ ] then
      throw "nixnative: policy missing required fields: ${lib.concatStringsSep ", " missing}"
    else if !(builtins.elem mergeOrder [ "defaults-first" "target-first" ]) then
      throw "nixnative: policy.flags.mergeOrder must be 'defaults-first' or 'target-first'"
    else
      policy;

  validateToolchain =
    toolchain:
    if toolchain ? toolset || toolchain ? policy then
      let
        required = [
          "name"
          "toolset"
          "policy"
          "languages"
          "linker"
          "targetPlatform"
        ];
        missing = builtins.filter (f: !(toolchain ? ${f})) required;
      in
      if missing != [ ] then
        throw "nixnative: toolchain missing required fields: ${lib.concatStringsSep ", " missing}"
      else
        toolchain
    else
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
      else
        mkToolchain {
          name = toolchain.name;
          toolset = mkToolset {
            inherit (toolchain) languages linker;
            bintools = toolchain.bintools or { };
          };
          policy = mkPolicy {
            inherit (toolchain) targetPlatform;
            runtimeInputs = toolchain.runtimeInputs or [ ];
            environment = toolchain.environment or { };
          };
        };

  # ==========================================================================
  # Capability Queries
  # ==========================================================================

  getCapabilities =
    toolchain:
    let
      tc = validateToolchain toolchain;
      langCaps =
        if tc.languages ? cpp then tc.languages.cpp.capabilities or { }
        else if tc.languages ? c then tc.languages.c.capabilities or { }
        else { };
      linkerCaps = tc.linker.capabilities or { };
    in
    {
      lto =
        if langCaps.lto or null == null then
          null
        else if !(linkerCaps.lto or false) then
          null
        else
          langCaps.lto;

      thinLto = (langCaps.lto.thin or false) && (linkerCaps.thinLto or false);
      sanitizers = langCaps.sanitizers or [ ];
      coverage = langCaps.coverage or false;
      icf = linkerCaps.icf or false;
      parallelLinking = linkerCaps.parallelLinking or false;
      splitDwarf = (langCaps.splitDwarf or false) && (linkerCaps.splitDwarf or false);
      colorDiagnostics = langCaps.colorDiagnostics or false;
      modules = langCaps.modules or false;
      pch = langCaps.pch or false;
    };

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
