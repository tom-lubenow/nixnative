# Dynamic derivations driver for nixnative
#
# Two modes are available:
#
# 1. Sequential mode (mkDynamicDriver): Single driver derivation that runs at
#    build time and sequentially scans/compiles all sources. Simple but not parallel.
#
# 2. Parallel mode (mkParallelDriver): Creates per-source wrapper derivations at
#    eval time, allowing Nix to build them in parallel. Uses dynamicOutputs to
#    reference wrapper outputs in the link derivation.
#
# The parallel mode architecture:
#   EVAL TIME:
#     - Create N compile wrapper derivations (one per source file)
#     - Create link derivation with dynamicOutputs referencing all wrappers
#
#   BUILD TIME:
#     - All compile wrappers run in parallel (Nix parallelism)
#     - Each wrapper: scan headers → create source tree → generate compile.drv → output
#     - Nix builds all compile.drv files
#     - Link derivation receives object paths via computed placeholders
#
# Requirements:
#   experimental-features = nix-command dynamic-derivations ca-derivations recursive-nix
#
{
  pkgs,
  lib,
  utils,
  nixPackage ? pkgs.nix,
}:

let
  inherit (lib) concatStringsSep mapAttrsToList;
  inherit (utils)
    sanitizePath
    sanitizeName
    toPathLike
    normalizeSources
    toDefineFlags
    ;

  # Scripts directory
  scriptsDir = ./scripts;

in
rec {
  # ==========================================================================
  # Feature Detection
  # ==========================================================================

  # Check if dynamic derivations are available
  # This checks for builtins.outputOf which is the key primitive
  hasDynamicDerivations = builtins ? outputOf;

  # Validate that dynamic derivations are available
  requireDynamicDerivations =
    if hasDynamicDerivations then
      true
    else
      throw ''
        nixnative: dynamic mode requires Nix with 'dynamic-derivations' experimental feature.
        Add to your nix.conf:
          experimental-features = nix-command flakes dynamic-derivations ca-derivations recursive-nix
      '';

  # ==========================================================================
  # Dynamic Driver
  # ==========================================================================

  # Create the driver derivation that produces compilation .drv files
  #
  # Arguments:
  #   name         - Target name
  #   root         - Source root directory
  #   sources      - List of source files
  #   toolchain    - Toolchain from mkToolchain
  #   includeDirs  - Include directories
  #   defines      - Preprocessor defines
  #   compileFlags - Raw compile flags
  #   langFlags    - Per-language raw flags
  #   flags        - Abstract flags (lto, sanitizers, etc.)
  #   headerOverrides - Tool-generated header overrides
  #   sourceOverrides - Tool-generated source overrides
  #   extraInputs  - Additional derivation inputs
  #
  mkDynamicDriver =
    {
      name,
      root,
      sources,
      toolchain,
      includeDirs ? [],
      defines ? [],
      compileFlags ? [],
      langFlags ? {},
      flags ? [],
      ldflags ? [],
      linkFlags ? [],
      headerOverrides ? {},
      sourceOverrides ? {},
      extraInputs ? [],
      outputType ? "executable",  # "executable", "sharedLibrary", or "staticArchive"
    }:
    let
      _ = requireDynamicDerivations;

      tc = toolchain;
      rootPath = sanitizePath { path = root; };

      # Normalize sources to translation units
      tus = normalizeSources { inherit root sources; };

      # Build include flags
      includeFlags = map (dir:
        if builtins.isString dir then "-I${dir}"
        else if builtins.isPath dir then "-I${dir}"
        else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
        else throw "mkDynamicDriver: includeDirs entries must be strings, paths, or {path} attrs"
      ) includeDirs;

      # Build define flags
      defineFlags = toDefineFlags defines;

      # Translate abstract flags
      translatedFlags = tc.translateFlags flags;

      # Platform-specific flags
      platformFlags = tc.getPlatformCompileFlags;

      # Combined flags for scanning and compilation
      allCompileFlags = platformFlags ++ translatedFlags ++ compileFlags;

      # Get compiler info
      cppCompiler = tc.getCompilerForLanguage "cpp";
      cCompiler = tc.getCompilerForLanguage "c";

      # Get linker info
      linkerDriverFlag = tc.linker.driverFlag;
      platformLinkerFlags = tc.getPlatformLinkerFlags;
      groupedLinkFlags = tc.wrapLibraryFlags linkFlags;
      rpathFlags = if tc.cxxRuntimeLibPath != null
        then [ "-Wl,-rpath,${tc.cxxRuntimeLibPath}" ]
        else [];
      finalLinkFlags = platformLinkerFlags ++ rpathFlags ++ ldflags ++ groupedLinkFlags;

      # Build source list JSON
      sourceList = map (tu: {
        rel = tu.relNorm;
        objectName = tu.objectName;
        lang = tc.getLanguageNameForFile tu.relNorm;
      }) tus;

      # Build header override lines for shell
      headerOverrideLines = mapAttrsToList (name: value: "${name}=${value}") headerOverrides;
      sourceOverrideLines = mapAttrsToList (name: value: "${name}=${value}") sourceOverrides;

      # Configuration passed to the driver script as JSON
      driverConfig = builtins.toJSON {
        inherit name outputType;
        sources = sourceList;
        includeDirs = includeFlags;
        defines = defineFlags;
        compileFlags = allCompileFlags;
        compilers = {
          c = cCompiler;
          cpp = cppCompiler;
        };
        defaultFlags = {
          c = tc.getDefaultFlagsForLanguage "c";
          cpp = tc.getDefaultFlagsForLanguage "cpp";
        };
        langFlags = {
          c = langFlags.c or [];
          cpp = langFlags.cpp or [];
        };
        # Link configuration
        linkConfig = {
          inherit linkerDriverFlag;
          linkFlags = finalLinkFlags;
          driverFlags = (tc.getDefaultFlagsForLanguage "cpp")
            ++ tc.getPlatformCompileFlags
            ++ (tc.translateFlags flags);
          ar = tc.ar;
          ranlib = tc.ranlib;
          # Include linker runtime inputs as store paths for the link derivation
          linkerInputs = map toString tc.linker.runtimeInputs;
        };
        system = pkgs.stdenv.hostPlatform.system;
      };

    in
    pkgs.stdenv.mkDerivation ({
      # Name MUST end in .drv for CA output path to be recognized as a derivation
      name = "${name}-driver.drv";

      # Content-addressed derivation with text output mode
      # The output will be a .drv file (link derivation)
      __contentAddressed = true;
      outputHashMode = "text";
      outputHashAlgo = "sha256";

      # Required for running nix commands inside the build
      requiredSystemFeatures = [ "recursive-nix" ];

      # Prevent self-references (not allowed in text output mode)
      NIX_NO_SELF_RPATH = true;

      nativeBuildInputs = tc.runtimeInputs ++ [
        nixPackage
        pkgs.python3
        pkgs.jq
        pkgs.coreutils
        pkgs.bash
      ] ++ map toPathLike extraInputs;

      src = rootPath;

      passAsFile = [ "driverConfig" "headerOverrides" "sourceOverrides" ];
      inherit driverConfig;
      headerOverrides = concatStringsSep "\n" headerOverrideLines;
      sourceOverrides = concatStringsSep "\n" sourceOverrideLines;

      # Pass scripts
      buildDriverScript = "${scriptsDir}/build-driver.sh";
      generateCompileDrvScript = "${scriptsDir}/generate-compile-drv.py";
      generateLinkDrvScript = "${scriptsDir}/generate-link-drv.py";

      # Pass paths for generated derivations
      BASH_PATH = "${pkgs.bash}/bin/bash";
      COREUTILS_PATH = "${pkgs.coreutils}";
      NIX_BIN = "${nixPackage}/bin/nix";

      # Enable experimental features for nested nix commands
      NIX_CONFIG = ''
        extra-experimental-features = nix-command ca-derivations dynamic-derivations
      '';

      passthru = {
        inherit name toolchain tus;
        inherit includeDirs defines compileFlags flags;
      };
      # Skip default phases
      dontUnpack = true;
      dontConfigure = true;
      dontInstall = true;
      dontFixup = true;

      buildPhase = ''
        runHook preBuild

        # Unset Nix wrapper environment variables
        unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
        unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET

        # Set up working directory
        work="$TMPDIR/work"
        mkdir -p "$work"

        # Copy source tree
        cp -r "$src"/* "$work/" || true
        chmod -R u+w "$work"

        # Apply header overrides from tools
        while IFS='=' read -r rel target; do
          [ -z "$rel" ] && continue
          mkdir -p "$work/$(dirname "$rel")"
          cp "$target" "$work/$rel"
        done < "$headerOverridesPath"

        # Apply source overrides from tools
        while IFS='=' read -r rel target; do
          [ -z "$rel" ] && continue
          mkdir -p "$work/$(dirname "$rel")"
          cp "$target" "$work/$rel"
        done < "$sourceOverridesPath"

        cd "$work"

        # Run the driver script
        # The script will output a .drv file to $out
        export DRIVER_CONFIG="$driverConfigPath"
        export WORK_DIR="$work"
        export GENERATE_DRV_SCRIPT="$generateCompileDrvScript"
        export GENERATE_LINK_DRV_SCRIPT="$generateLinkDrvScript"

        bash "$buildDriverScript"

        runHook postBuild
      '';
    } // tc.environment);

  # ==========================================================================
  # Dynamic Output Reference
  # ==========================================================================

  # Get a reference to a dynamic derivation's output
  # This returns a placeholder that Nix resolves at build time
  #
  mkDynamicOutputRef = driverDrv: outputName:
    builtins.outputOf
      (builtins.unsafeDiscardOutputDependency driverDrv.outPath)
      outputName;

  # Get reference to the objects manifest from a driver
  mkObjectsRef = driverDrv:
    mkDynamicOutputRef driverDrv "out";

  # ==========================================================================
  # Parallel Compilation (Per-Source Wrapper Derivations)
  # ==========================================================================

  # Create a compile wrapper derivation for a single source file.
  # This wrapper:
  # 1. Scans the source for headers
  # 2. Creates a minimal source tree
  # 3. Generates a compile derivation JSON
  # 4. Outputs the compile .drv file (text mode)
  #
  # All wrappers can be built in parallel by Nix!
  #
  mkCompileWrapper = {
    tu,                # Translation unit from normalizeSources
    rootPath,          # Source root store path
    toolchain,         # Toolchain
    includeFlags,      # Include directory flags
    defineFlags,       # Preprocessor defines
    compileFlags,      # Compile flags
    langFlags,         # Per-language flags
    linkerDriverFlag,  # Linker flag (for consistency)
    headerOverrides ? {},
    sourceOverrides ? {},
    extraInputs ? [],
  }:
  let
    tc = toolchain;
    lang = tc.getLanguageNameForFile tu.relNorm;
    compiler = tc.getCompilerForLanguage lang;
    defaultFlags = tc.getDefaultFlagsForLanguage lang;
    langSpecificFlags = langFlags.${lang} or [];

    # Build header/source override lines for shell
    headerOverrideLines = mapAttrsToList (name: value: "${name}=${value}") headerOverrides;
    sourceOverrideLines = mapAttrsToList (name: value: "${name}=${value}") sourceOverrides;

  in pkgs.stdenv.mkDerivation ({
    # Name must end in .drv for text mode output recognition
    name = "compile-${sanitizeName tu.relNorm}.drv";

    # Content-addressed derivation with text output mode
    # The output is a .drv file (compilation derivation)
    __contentAddressed = true;
    outputHashMode = "text";
    outputHashAlgo = "sha256";

    # Required for running nix commands inside the build
    requiredSystemFeatures = [ "recursive-nix" ];

    # Prevent self-references
    NIX_NO_SELF_RPATH = true;

    nativeBuildInputs = tc.runtimeInputs ++ [
      nixPackage
      pkgs.python3
      pkgs.coreutils
      pkgs.bash
    ] ++ map toPathLike extraInputs;

    src = rootPath;

    # Source file info
    SOURCE_REL = tu.relNorm;
    OBJECT_NAME = tu.objectName;
    LANG = lang;
    COMPILER = compiler;
    DEFAULT_FLAGS = concatStringsSep " " defaultFlags;
    COMPILE_FLAGS = concatStringsSep " " compileFlags;
    INCLUDE_FLAGS = concatStringsSep " " includeFlags;
    DEFINE_FLAGS = concatStringsSep " " defineFlags;
    LANG_FLAGS = concatStringsSep " " langSpecificFlags;
    LINKER_FLAG = linkerDriverFlag;
    SYSTEM = pkgs.stdenv.hostPlatform.system;

    # Paths for scripts and tools
    GENERATE_DRV_SCRIPT = "${scriptsDir}/generate-compile-drv.py";
    BASH_PATH = "${pkgs.bash}/bin/bash";
    COREUTILS_PATH = "${pkgs.coreutils}";
    NIX_BIN = "${nixPackage}/bin/nix";

    # Override files passed as file
    passAsFile = [ "headerOverrides" "sourceOverrides" ];
    headerOverrides = concatStringsSep "\n" headerOverrideLines;
    sourceOverrides = concatStringsSep "\n" sourceOverrideLines;

    # Enable experimental features for nested nix commands
    NIX_CONFIG = ''
      extra-experimental-features = nix-command ca-derivations dynamic-derivations
    '';

    # Skip default phases
    dontUnpack = true;
    dontConfigure = true;
    dontInstall = true;
    dontFixup = true;

    buildPhase = ''
      runHook preBuild

      # Set up working directory
      work="$TMPDIR/work"
      mkdir -p "$work"

      # Copy source tree
      cp -r "$src"/* "$work/" || true
      chmod -R u+w "$work"

      # Apply header overrides
      while IFS='=' read -r rel target; do
        [ -z "$rel" ] && continue
        mkdir -p "$work/$(dirname "$rel")"
        cp "$target" "$work/$rel"
      done < "$headerOverridesPath"

      # Apply source overrides
      while IFS='=' read -r rel target; do
        [ -z "$rel" ] && continue
        mkdir -p "$work/$(dirname "$rel")"
        cp "$target" "$work/$rel"
      done < "$sourceOverridesPath"

      # Run the compile wrapper script
      bash ${scriptsDir}/compile-wrapper.sh

      runHook postBuild
    '';

    passthru = {
      inherit tu lang;
      objectName = tu.objectName;
    };
  } // tc.environment);

  # Create a parallel driver with per-source compile wrappers
  #
  # This is the preferred mode for parallel compilation. It creates:
  # 1. N compile wrapper derivations (one per source file) at eval time
  # 2. A link derivation that uses dynamicOutputs to depend on all wrappers
  #
  # Nix can then build all compile wrappers in parallel!
  #
  mkParallelDriver = {
    name,
    root,
    sources,
    toolchain,
    includeDirs ? [],
    defines ? [],
    compileFlags ? [],
    langFlags ? {},
    flags ? [],
    ldflags ? [],
    linkFlags ? [],
    headerOverrides ? {},
    sourceOverrides ? {},
    extraInputs ? [],
    outputType ? "executable",
  }:
  let
    _ = requireDynamicDerivations;

    tc = toolchain;
    rootPath = sanitizePath { path = root; };

    # Normalize sources to translation units
    tus = normalizeSources { inherit root sources; };

    # Build include flags
    includeFlags = map (dir:
      if builtins.isString dir then "-I${dir}"
      else if builtins.isPath dir then "-I${dir}"
      else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
      else throw "mkParallelDriver: includeDirs entries must be strings, paths, or {path} attrs"
    ) includeDirs;

    # Build define flags
    defineFlags = toDefineFlags defines;

    # Translate abstract flags
    translatedFlags = tc.translateFlags flags;

    # Platform-specific flags
    platformFlags = tc.getPlatformCompileFlags;

    # Combined flags for compilation
    allCompileFlags = platformFlags ++ translatedFlags ++ compileFlags;

    # Get linker info
    linkerDriverFlag = tc.linker.driverFlag;
    platformLinkerFlags = tc.getPlatformLinkerFlags;
    groupedLinkFlags = tc.wrapLibraryFlags linkFlags;
    rpathFlags = if tc.cxxRuntimeLibPath != null
      then [ "-Wl,-rpath,${tc.cxxRuntimeLibPath}" ]
      else [];
    finalLinkFlags = platformLinkerFlags ++ rpathFlags ++ ldflags ++ groupedLinkFlags;

    # Create a compile wrapper for each source file
    compileWrappers = map (tu: {
      wrapper = mkCompileWrapper {
        inherit tu rootPath toolchain headerOverrides sourceOverrides extraInputs;
        inherit includeFlags defineFlags linkerDriverFlag;
        compileFlags = allCompileFlags;
        langFlags = {
          c = langFlags.c or [];
          cpp = langFlags.cpp or [];
        };
      };
      objectName = tu.objectName;
    }) tus;

    # Generate the list of wrapper info for the link script
    wrapperInfoJson = builtins.toJSON (map (cw: {
      wrapper_drv = cw.wrapper.drvPath;
      object_name = cw.objectName;
    }) compileWrappers);

    # Link configuration
    cppCompiler = tc.getCompilerForLanguage "cpp";
    linkConfigJson = builtins.toJSON {
      compiler = cppCompiler;
      linkerDriverFlag = linkerDriverFlag;
      linkFlags = finalLinkFlags;
      driverFlags = (tc.getDefaultFlagsForLanguage "cpp")
        ++ tc.getPlatformCompileFlags
        ++ (tc.translateFlags flags);
      ar = tc.ar;
      ranlib = tc.ranlib;
      linkerInputs = map toString tc.linker.runtimeInputs;
    };

    # Create a link wrapper derivation that generates the link drv at build time
    # This is CA/text mode, outputs a .drv file
    linkWrapper = pkgs.stdenv.mkDerivation ({
      name = "${name}-link.drv";

      # Content-addressed derivation with text output mode
      __contentAddressed = true;
      outputHashMode = "text";
      outputHashAlgo = "sha256";

      # Required for running nix commands inside the build
      requiredSystemFeatures = [ "recursive-nix" ];

      # Prevent self-references
      NIX_NO_SELF_RPATH = true;

      nativeBuildInputs = [
        nixPackage
        pkgs.python3
        pkgs.coreutils
        pkgs.bash
      ];

      inherit wrapperInfoJson linkConfigJson;
      passAsFile = [ "wrapperInfoJson" "linkConfigJson" ];

      BASH_PATH = "${pkgs.bash}/bin/bash";
      COREUTILS_PATH = "${pkgs.coreutils}";

      # Enable experimental features
      NIX_CONFIG = ''
        extra-experimental-features = nix-command ca-derivations dynamic-derivations
      '';

      # Skip default phases
      dontUnpack = true;
      dontConfigure = true;
      dontInstall = true;
      dontFixup = true;

      buildPhase = ''
        runHook preBuild

        python3 ${scriptsDir}/generate-link-drv.py \
          --name "${name}" \
          --output-type "${outputType}" \
          --compile-wrappers "$wrapperInfoJsonPath" \
          --link-config "$linkConfigJsonPath" \
          --system "${pkgs.stdenv.hostPlatform.system}" \
          --output "$TMPDIR/link.json"

        # Use nix derivation add to create the .drv and copy to $out
        ${nixPackage}/bin/nix derivation add < "$TMPDIR/link.json" > "$TMPDIR/drv_path"
        drv_path=$(cat "$TMPDIR/drv_path")
        cp "$drv_path" "$out"

        runHook postBuild
      '';
    } // tc.environment);

  in {
    # The link wrapper derivation (outputs the link .drv file)
    inherit linkWrapper;

    # All the compile wrappers (for inspection)
    inherit compileWrappers;

    # Get reference to the final linked artifact
    # Build order: linkWrapper → link.drv → (compile wrappers in parallel) → compile drvs → link
    out = builtins.outputOf
      (builtins.unsafeDiscardOutputDependency linkWrapper.outPath)
      "out";

    passthru = {
      inherit name toolchain tus compileWrappers linkWrapper;
      inherit includeDirs defines compileFlags flags;
    };
  };
}
