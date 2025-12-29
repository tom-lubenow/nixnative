# Link primitive for nixnative dynamic derivations
#
# This module provides mkLinkWrapper which creates a link derivation
# from object references. It links objects into executables or shared libraries.
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
  inherit (lib) concatStringsSep;
  inherit (utils) sanitizeName;

  # Scripts directory
  scriptsDir = ./scripts;

in
rec {
  # ==========================================================================
  # Link Wrapper
  # ==========================================================================

  # Create a link derivation from object references.
  #
  # This creates a CA text-mode derivation that outputs a link .drv file.
  # The link .drv, when built, links all objects into the final artifact.
  #
  # Arguments:
  #   name         - Target name
  #   toolchain    - Toolchain from mkToolchain
  #   objectRefs   - List of { wrapper, objectName, ref, path } from mkCompileSet
  #                  or { path } for external libraries
  #   outputType   - "executable" or "sharedLibrary"
  #   ldflags      - Additional linker flags
  #   linkFlags    - Library link flags (e.g., -lz, /path/to/lib.a)
  #   flags        - Abstract flags (lto, sanitizers, etc.)
  #
  # Returns:
  #   {
  #     drv = <link-wrapper-drv>;  # The wrapper derivation
  #     out = <builtins.outputOf placeholder>;  # Reference to final artifact
  #     executablePath = <placeholder>/bin/${name};  # For executables
  #     sharedLibPath = <placeholder>/lib/lib${name}.so;  # For shared libs
  #   }
  #
  mkLinkWrapper = {
    name,
    toolchain,
    objectRefs,
    outputType ? "executable",
    ldflags ? [],
    linkFlags ? [],
    flags ? [],
  }:
  let
    tc = toolchain;

    # Separate objectRefs with wrappers (dynamic) from direct paths (external)
    dynamicRefs = builtins.filter (ref: ref ? wrapper && ref.wrapper != null) objectRefs;
    directPaths = builtins.filter (ref: !(ref ? wrapper) || ref.wrapper == null) objectRefs;

    # Wrapper info for the script
    # Strip context from drvPath - dependency tracked via dynamicOutputs, not string context
    wrapperInfo = map (ref: {
      wrapper_drv = builtins.unsafeDiscardStringContext ref.wrapper.drvPath;
      object_name = ref.objectName;
    }) dynamicRefs;

    wrapperInfoJson = builtins.toJSON wrapperInfo;

    # Translate abstract flags (for LTO compatibility at link time)
    translatedLinkFlags = tc.translateFlags flags;

    # Platform linker flags
    platformLinkerFlags = tc.getPlatformLinkerFlags;

    # Link configuration
    linkConfig = {
      compiler = tc.getCompilerForLanguage "cpp";
      linkerDriverFlag = tc.linker.driverFlag;
      linkFlags = platformLinkerFlags ++ translatedLinkFlags ++ ldflags ++ linkFlags
                  ++ (map (ref: ref.path) directPaths);
      driverFlags = [];
      linkerInputs = tc.linker.runtimeInputs or [];
    };

    linkConfigJson = builtins.toJSON linkConfig;

    wrapper = pkgs.stdenv.mkDerivation ({
      # Name ends in .drv for text mode output to be recognized as derivation
      name = "${name}-link.drv";

      # Content-addressed derivation with text output mode
      # The output IS the .drv file
      __contentAddressed = true;
      outputHashMode = "text";
      outputHashAlgo = "sha256";

      # Required for running nix commands inside the build
      requiredSystemFeatures = [ "recursive-nix" ];

      nativeBuildInputs = tc.runtimeInputs ++ [
        nixPackage
        pkgs.python3
        pkgs.coreutils
        pkgs.bash
      ];

      # Pass configuration
      inherit wrapperInfoJson linkConfigJson;
      passAsFile = [ "wrapperInfoJson" "linkConfigJson" ];

      # Environment for link
      BASH_PATH = "${pkgs.bash}/bin/bash";
      COREUTILS_PATH = "${pkgs.coreutils}";
      NIX_BIN = "${nixPackage}/bin/nix";

      # Enable experimental features for nested nix commands
      NIX_CONFIG = ''
        extra-experimental-features = nix-command ca-derivations dynamic-derivations
      '';

      dontUnpack = true;
      dontConfigure = true;
      dontInstall = true;
      dontFixup = true;

      buildPhase = ''
        runHook preBuild

        # Generate link derivation using Python script
        python3 ${scriptsDir}/generate-link-drv.py \
          --name "${name}" \
          --output-type "${outputType}" \
          --compile-wrappers "$wrapperInfoJsonPath" \
          --link-config "$linkConfigJsonPath" \
          --system "${pkgs.stdenv.hostPlatform.system}" \
          --output "$TMPDIR/link.json"

        # Add to nix store
        drv_path=$($NIX_BIN derivation add < "$TMPDIR/link.json")
        echo "Created link derivation: $drv_path" >&2

        # Output the .drv file itself (text mode)
        cp "$drv_path" "$out"

        runHook postBuild
      '';

      passthru = {
        inherit outputType;
      };
    } // tc.environment);

    # Reference to the link.drv's output (the actual binary)
    # The wrapper's output IS the link.drv (text mode), so we only need
    # one level of outputOf to get the binary
    linkOut = builtins.outputOf
      (builtins.unsafeDiscardOutputDependency wrapper.outPath)
      "out";

  in {
    drv = wrapper;
    out = linkOut;
    executablePath = "${linkOut}/bin/${name}";
    sharedLibPath = "${linkOut}/lib/lib${name}.so";
  };

  # ==========================================================================
  # Convenience Wrappers
  # ==========================================================================

  # Create an executable from object references
  mkExecutableLink = args: mkLinkWrapper (args // { outputType = "executable"; });

  # Create a shared library from object references
  mkSharedLibLink = args: mkLinkWrapper (args // { outputType = "sharedLibrary"; });
}
