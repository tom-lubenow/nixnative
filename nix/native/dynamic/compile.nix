# Compile primitives for nixnative dynamic derivations
#
# This module provides:
# - mkCompileWrapper: Create a wrapper derivation for a single source file
# - mkCompileSet: Compile multiple sources, returning object references
#
# These primitives produce object files only - NO linking.
# Consumers (executables, shared libs) collect objectRefs and link them.
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
  # Object Reference Helpers
  # ==========================================================================

  # Get a reference to a dynamic derivation's output
  # Returns a placeholder that Nix resolves at build time
  mkDynamicOutputRef = wrapper: outputName:
    builtins.outputOf
      (builtins.unsafeDiscardOutputDependency wrapper.outPath)
      outputName;

  # Create an object reference from a compile wrapper
  # This is the standard way to reference compiled objects
  mkObjectRef = wrapper:
    let
      ref = mkDynamicOutputRef wrapper "out";
    in {
      inherit wrapper;
      objectName = wrapper.passthru.objectName;
      ref = ref;
      # Full path to the object file (for use in link commands)
      path = "${ref}/${wrapper.passthru.objectName}";
    };

  # ==========================================================================
  # Compile Wrapper
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
    langFlags,         # Per-language flags { c = [...]; cpp = [...]; }
    linkerDriverFlag ? "",  # Linker flag (for consistency in object files)
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

  # ==========================================================================
  # Compile Set
  # ==========================================================================

  # Create compile wrappers for multiple sources and return object references.
  # This is the main entry point for compilation - NO linking happens here.
  #
  # Arguments:
  #   name         - Base name for derivations
  #   root         - Source root directory
  #   sources      - List of source files (globs, paths, or {rel, ...} attrs)
  #   toolchain    - Toolchain from mkToolchain
  #   includeDirs  - Include directories
  #   defines      - Preprocessor defines
  #   compileFlags - Raw compile flags
  #   langFlags    - Per-language raw flags { c = [...]; cpp = [...]; }
  #   flags        - Abstract flags (lto, sanitizers, etc.)
  #   headerOverrides - Tool-generated header overrides
  #   sourceOverrides - Tool-generated source overrides
  #   extraInputs  - Additional derivation inputs
  #
  # Returns:
  #   {
  #     wrappers = [ <compile-wrapper-drv> ... ];
  #     objectRefs = [ { wrapper, objectName, ref, path } ... ];
  #     tus = [ ... ];  # Translation units for reference
  #   }
  #
  mkCompileSet = {
    name,
    root,
    sources,
    toolchain,
    includeDirs ? [],
    defines ? [],
    compileFlags ? [],
    langFlags ? {},
    flags ? [],
    headerOverrides ? {},
    sourceOverrides ? {},
    extraInputs ? [],
  }:
  let
    _ = requireDynamicDerivations;

    tc = toolchain;
    rootPath = sanitizePath { path = root; };

    # Normalize sources to translation units
    tus = normalizeSources { inherit root sources; };

    # Build include flags
    includeFlags' = map (dir:
      if builtins.isString dir then "-I${dir}"
      else if builtins.isPath dir then "-I${dir}"
      else if builtins.isAttrs dir && dir ? path then "-I${dir.path}"
      else throw "mkCompileSet: includeDirs entries must be strings, paths, or {path} attrs"
    ) includeDirs;

    # Build define flags
    defineFlags = toDefineFlags defines;

    # Translate abstract flags
    translatedFlags = tc.translateFlags flags;

    # Platform-specific flags
    platformFlags = tc.getPlatformCompileFlags;

    # Combined flags for compilation
    allCompileFlags = platformFlags ++ translatedFlags ++ compileFlags;

    # Get linker info (for consistency in object files)
    linkerDriverFlag = tc.linker.driverFlag;

    # Create a compile wrapper for each translation unit
    wrappers = map (tu:
      mkCompileWrapper {
        inherit tu rootPath toolchain;
        includeFlags = includeFlags';
        inherit defineFlags;
        compileFlags = allCompileFlags;
        inherit langFlags linkerDriverFlag;
        inherit headerOverrides sourceOverrides extraInputs;
      }
    ) tus;

    # Create object references for each wrapper
    objectRefs = map mkObjectRef wrappers;

  in {
    inherit wrappers objectRefs tus;

    # Convenience: all object paths (for debugging/inspection)
    objectPaths = map (ref: ref.path) objectRefs;
  };
}
