# Link step for nixnative
#
# Links object files into executables, shared libraries, or static archives.
# Uses the linker abstraction from the toolchain.
#
{
  pkgs,
  lib,
  platform,
}:

let
  inherit (lib) concatStringsSep concatMapStrings;

in
rec {
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
    {
      toolchain,
      name,
      objects,
      flags ? [ ],
      extraCxxFlags ? [ ],
      ldflags ? [ ],
      linkFlags ? [ ],
      outputDir ? "bin",
      outputName ? name,
      extraFlags ? [ ],
      extraInputs ? [ ],
    }:
    let
      tc = toolchain;
      targetPlatform = tc.targetPlatform;

      # Translate abstract flags (for LTO compatibility at link time)
      translatedFlags = tc.translateFlags flags;

      # Get linker driver flag (-fuse-ld=lld, etc.)
      linkerDriverFlag = if tc.linker.driverFlag != "" then [ tc.linker.driverFlag ] else [ ];

      # Platform-specific linker flags from linker
      platformLinkerFlags = tc.getPlatformLinkerFlags;

      # Wrap library flags for platform (--start-group on Linux)
      groupedLinkFlags = tc.wrapLibraryFlags linkFlags;

      # Add rpath for C++ runtime library (needed on Linux for libstdc++)
      rpathFlags = if tc.cxxRuntimeLibPath != null then [ "-Wl,-rpath,${tc.cxxRuntimeLibPath}" ] else [ ];

      # Combine all link flags
      finalLinkFlags = platformLinkerFlags ++ rpathFlags ++ ldflags ++ groupedLinkFlags;

      # Combine all C++ flags
      allCxxFlags =
        (tc.getDefaultFlagsForLanguage "cpp") ++ tc.getPlatformCompileFlags ++ translatedFlags ++ extraCxxFlags;
    in
    pkgs.runCommand name
      (
        {
          buildInputs = tc.runtimeInputs ++ extraInputs;
        }
        // tc.environment
      )
      ''
        set -euo pipefail
        # Unset Nix wrapper environment variables that interfere with our explicit flags
        unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
        unset NIX_LDFLAGS NIX_LDFLAGS_FOR_TARGET
        mkdir -p "$out/${outputDir}"
        ${tc.getCompilerForLanguage "cpp"} \
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
    {
      toolchain,
      name,
      objects,
      flags ? [ ],
      extraCxxFlags ? [ ],
      ldflags ? [ ],
      linkFlags ? [ ],
      extraInputs ? [ ],
    }:
    mkLinkStep {
      inherit
        toolchain
        name
        objects
        flags
        extraCxxFlags
        ldflags
        linkFlags
        extraInputs
        ;
      outputDir = "bin";
    };

  # ==========================================================================
  # Shared Library Linking
  # ==========================================================================

  linkSharedLibrary =
    {
      toolchain,
      name,
      objects,
      flags ? [ ],
      extraCxxFlags ? [ ],
      ldflags ? [ ],
      linkFlags ? [ ],
      extraInputs ? [ ],
    }:
    let
      targetPlatform = toolchain.targetPlatform;
      sharedExt = builtins.substring 1 100 (platform.sharedLibExtension targetPlatform); # Strip leading "."
      sharedName = "lib${name}.${sharedExt}";
    in
    mkLinkStep {
      inherit
        toolchain
        objects
        flags
        extraCxxFlags
        ldflags
        linkFlags
        extraInputs
        ;
      name = "shared-${name}";
      outputDir = "lib";
      outputName = sharedName;
      extraFlags = [ "-shared" ];
    }
    // {
      sharedLibraryName = sharedName;
      sharedLibraryExt = sharedExt;
    };

  # ==========================================================================
  # Static Archive Creation
  # ==========================================================================

  createStaticArchive =
    {
      toolchain,
      name,
      objects,
    }:
    let
      tc = toolchain;
      archiveName = "lib${name}.a";

      archiveScript = concatMapStrings (obj: "${tc.ar} rcs \"${archiveName}\" \"${obj}\"\n") objects;
    in
    pkgs.runCommand "archive-${name}"
      (
        {
          buildInputs = tc.runtimeInputs;
        }
        // tc.environment
      )
      ''
        set -euo pipefail
        mkdir -p "$out/lib"
        ${archiveScript}
        ${if tc.ranlib != null then "${tc.ranlib} \"${archiveName}\"" else ""}
        mv "${archiveName}" "$out/lib/"
      ''
    // {
      archiveName = archiveName;
      archivePath = "$out/lib/${archiveName}";
    };
}
