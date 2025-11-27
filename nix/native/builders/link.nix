# Link step for nixnative
#
# Links object files into executables, shared libraries, or static archives.
# Uses the linker abstraction from the toolchain.
#
{ pkgs, lib }:

let
  inherit (lib) concatStringsSep concatMapStrings optional;

in rec {
  # ==========================================================================
  # Link Step (Core)
  # ==========================================================================

  # Generic link step using toolchain's linker
  #
  # Arguments:
  #   toolchain   - Toolchain from mkToolchain
  #   name        - Output name
  #   objects     - List of object file paths
  #   flags       - Abstract flags (for LTO, etc.)
  #   extraCxxFlags - Additional C++ flags passed to driver
  #   ldflags     - Additional linker flags
  #   linkFlags   - Library link flags (gets grouped on Linux)
  #   outputDir   - Output subdirectory (default: "bin")
  #   outputName  - Output filename (default: name)
  #   extraFlags  - Extra driver flags (e.g., "-shared")
  #
  mkLinkStep =
    { toolchain
    , name
    , objects
    , flags ? []
    , extraCxxFlags ? []
    , ldflags ? []
    , linkFlags ? []
    , outputDir ? "bin"
    , outputName ? name
    , extraFlags ? []
    }:
    let
      tc = toolchain;
      targetPlatform = tc.targetPlatform;

      # Translate abstract flags (for LTO compatibility at link time)
      translatedFlags = tc.translateFlags flags;

      # Get linker driver flag (-fuse-ld=lld, etc.)
      linkerDriverFlag =
        if tc.linker.driverFlag != ""
        then [ tc.linker.driverFlag ]
        else [];

      # Platform-specific linker flags from linker
      platformLinkerFlags = tc.getPlatformLinkerFlags;

      # Wrap library flags for platform (--start-group on Linux)
      groupedLinkFlags = tc.wrapLibraryFlags linkFlags;

      # Combine all link flags
      finalLinkFlags =
        platformLinkerFlags
        ++ ldflags
        ++ groupedLinkFlags;

      # Combine all C++ flags
      allCxxFlags =
        tc.getDefaultCxxFlags
        ++ tc.getPlatformCompileFlags
        ++ translatedFlags
        ++ extraCxxFlags;
    in
    pkgs.runCommand name
      ({
        buildInputs = tc.runtimeInputs;
      } // tc.environment)
      ''
        set -euo pipefail
        mkdir -p "$out/${outputDir}"
        ${tc.getCXX} \
          ${concatStringsSep " " extraFlags} \
          ${concatStringsSep " " linkerDriverFlag} \
          ${concatStringsSep " " allCxxFlags} \
          ${concatStringsSep " " objects} \
          ${concatStringsSep " " finalLinkFlags} \
          -o "$out/${outputDir}/${outputName}"
      '';

  # ==========================================================================
  # Executable Linking
  # ==========================================================================

  linkExecutable =
    { toolchain
    , name
    , objects
    , flags ? []
    , extraCxxFlags ? []
    , ldflags ? []
    , linkFlags ? []
    }:
    mkLinkStep {
      inherit toolchain name objects flags extraCxxFlags ldflags linkFlags;
      outputDir = "bin";
    };

  # ==========================================================================
  # Shared Library Linking
  # ==========================================================================

  linkSharedLibrary =
    { toolchain
    , name
    , objects
    , flags ? []
    , extraCxxFlags ? []
    , ldflags ? []
    , linkFlags ? []
    }:
    let
      targetPlatform = toolchain.targetPlatform;
      sharedExt = if targetPlatform.isDarwin then "dylib" else "so";
      sharedName = "lib${name}.${sharedExt}";
    in
    mkLinkStep {
      inherit toolchain objects flags extraCxxFlags ldflags linkFlags;
      name = "shared-${name}";
      outputDir = "lib";
      outputName = sharedName;
      extraFlags = [ "-shared" ];
    } // {
      sharedLibraryName = sharedName;
      sharedLibraryExt = sharedExt;
    };

  # ==========================================================================
  # Static Archive Creation
  # ==========================================================================

  createStaticArchive =
    { toolchain
    , name
    , objects
    }:
    let
      tc = toolchain;
      archiveName = "lib${name}.a";

      archiveScript =
        concatMapStrings (obj: "${tc.ar} rcs \"${archiveName}\" \"${obj}\"\n") objects;
    in
    pkgs.runCommand "archive-${name}"
      ({
        buildInputs =
          tc.runtimeInputs
          ++ optional pkgs.stdenv.hostPlatform.isDarwin pkgs.darwin.cctools;
      } // tc.environment)
      ''
        set -euo pipefail
        mkdir -p "$out/lib"
        ${archiveScript}
        ${if tc.ranlib != null then "${tc.ranlib} \"${archiveName}\"" else ""}
        mv "${archiveName}" "$out/lib/"
      '' // {
        archiveName = archiveName;
        archivePath = "$out/lib/${archiveName}";
      };
}
