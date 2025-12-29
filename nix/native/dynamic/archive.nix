# Archive primitive for nixnative dynamic derivations
#
# This module provides mkArchiveWrapper which creates a static archive (.a)
# from object references.
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
  # Archive Wrapper
  # ==========================================================================

  # Create an archive derivation from object references.
  #
  # This creates a CA text-mode derivation that outputs an archive .drv file.
  # The archive .drv, when built, creates a .a file from the objects.
  #
  # Arguments:
  #   name         - Archive name (will produce lib${name}.a)
  #   toolchain    - Toolchain from mkToolchain
  #   objectRefs   - List of { wrapper, objectName, ref, path } from mkCompileSet
  #
  # Returns:
  #   {
  #     drv = <archive-wrapper-drv>;  # The wrapper derivation
  #     out = <builtins.outputOf placeholder>;  # Reference to final archive
  #     archivePath = <placeholder>/lib/lib${name}.a;
  #   }
  #
  mkArchiveWrapper = {
    name,
    toolchain,
    objectRefs,
  }:
  let
    tc = toolchain;

    # Get ar and ranlib from toolchain
    ar = tc.ar or "${pkgs.binutils}/bin/ar";
    ranlib = tc.ranlib or "${pkgs.binutils}/bin/ranlib";

    # Build inputDrvs with dynamicOutputs for each wrapper
    # Format: { "/path/to.drv" = { outputs = []; dynamicOutputs = { "out" = { outputs = ["out"]; dynamicOutputs = {}; } }; }; }
    inputDrvsJson = builtins.toJSON (
      builtins.listToAttrs (map (objRef:
        {
          name = objRef.wrapper.drvPath;
          value = {
            outputs = [];
            dynamicOutputs = {
              out = {
                outputs = [ "out" ];
                dynamicOutputs = {};
              };
            };
          };
        }
      ) (builtins.filter (ref: ref.wrapper != null) objectRefs))
    );

    # Object paths for the archive command
    objectPaths = map (ref: ref.path) objectRefs;

    # Wrapper info for the script
    wrapperInfo = map (ref: {
      wrapper_drv = ref.wrapper.drvPath;
      object_name = ref.objectName;
    }) (builtins.filter (ref: ref.wrapper != null) objectRefs);

    wrapperInfoJson = builtins.toJSON wrapperInfo;

    # Archive configuration
    archiveConfig = {
      inherit name;
      ar = ar;
      ranlib = ranlib;
      system = pkgs.stdenv.hostPlatform.system;
      bashPath = "${pkgs.bash}/bin/bash";
      coreutilsPath = "${pkgs.coreutils}";
    };

    archiveConfigJson = builtins.toJSON archiveConfig;

    wrapper = pkgs.stdenv.mkDerivation ({
      name = "${name}-archive.drv";

      # Content-addressed derivation with text output mode
      __contentAddressed = true;
      outputHashMode = "text";
      outputHashAlgo = "sha256";

      # Required for running nix commands inside the build
      requiredSystemFeatures = [ "recursive-nix" ];

      nativeBuildInputs = [
        nixPackage
        pkgs.python3
        pkgs.coreutils
        pkgs.bash
        pkgs.jq
      ];

      # Pass configuration
      inherit wrapperInfoJson archiveConfigJson inputDrvsJson;
      passAsFile = [ "wrapperInfoJson" "archiveConfigJson" "inputDrvsJson" ];

      # Environment for archive generation
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

        # Generate archive derivation using Python script
        python3 ${scriptsDir}/generate-archive-drv.py \
          --name "${name}" \
          --wrapper-info "$wrapperInfoJsonPath" \
          --archive-config "$archiveConfigJsonPath" \
          --system "${pkgs.stdenv.hostPlatform.system}" \
          --output "$TMPDIR/archive.json"

        # Add to nix store
        drv_path=$($NIX_BIN derivation add < "$TMPDIR/archive.json")
        echo "Created archive derivation: $drv_path" >&2

        # Output the .drv file itself (text mode)
        cp "$drv_path" "$out"

        runHook postBuild
      '';

      passthru = {
        archiveName = "lib${name}.a";
      };
    } // tc.environment);

    # Reference to the wrapper's output (the archive.drv path)
    wrapperOut = builtins.outputOf
      (builtins.unsafeDiscardOutputDependency wrapper.outPath)
      "out";

    # Reference to the archive.drv's output (the actual archive)
    # This is a computed output - we reference the output of the drv that the wrapper produces
    archiveOut = builtins.outputOf wrapperOut "out";

  in {
    drv = wrapper;
    out = archiveOut;
    archivePath = "${archiveOut}/lib/lib${name}.a";
    archiveName = "lib${name}.a";
  };
}
