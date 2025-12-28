# Dynamic derivations driver for nixnative
#
# Creates a driver derivation that:
# 1. Runs at build time (not evaluation time)
# 2. Scans sources for header dependencies
# 3. Generates compilation .drv files via `nix derivation add`
# 4. Outputs a LINK derivation (.drv file) that depends on all compilation derivations
#
# The output is a .drv file (outputHashMode = "text") that Nix will automatically
# build to produce the final linked artifact.
#
# This eliminates IFD (Import From Derivation) by deferring dependency
# discovery to build time using Nix's dynamic derivations feature.
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
}
