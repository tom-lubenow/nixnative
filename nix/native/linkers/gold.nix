# Gold linker implementation for nixnative
#
# Gold is the GNU linker designed for ELF. It's faster than GNU ld
# for large C++ projects but has fewer features than LLD or mold.
#
{
  pkgs,
  lib,
  mkLinker,
  goldCapabilities,
}:

let
  inherit (lib) optionals;
  targetPlatform = pkgs.stdenv.targetPlatform;

  # Gold is only available on Linux (ELF systems)
  isSupported = targetPlatform.isLinux;

in
rec {
  # ==========================================================================
  # Gold Linker
  # ==========================================================================

  gold =
    if isSupported then
      mkLinker {
        name = "gold";
        binary = "${pkgs.binutils}/bin/ld.gold";
        # Use full path so compiler doesn't need ld.gold on PATH
        driverFlag = "-fuse-ld=${pkgs.binutils}/bin/ld.gold";

        capabilities = goldCapabilities;

        platformFlags =
          platform:
          if platform.isLinux then
            [
              "-Wl,--enable-new-dtags"
            ]
          else
            [ ];

        runtimeInputs = [ pkgs.binutils ];
        environment = { };
      }
    else
      null;

  # ==========================================================================
  # Availability Check
  # ==========================================================================

  isAvailable = isSupported;
}
