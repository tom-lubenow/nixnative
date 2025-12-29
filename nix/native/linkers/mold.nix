# Mold linker implementation for nixnative
#
# Mold is a high-performance linker that aims to be faster than all
# existing Unix linkers. Best used on Linux; limited macOS support.
#
{
  pkgs,
  lib,
  mkLinker,
  moldCapabilities,
}:

let
  inherit (lib) optionals;
  targetPlatform = pkgs.stdenv.targetPlatform;

  # Mold is primarily a Linux linker
  # sold (macOS port) exists but is commercial
  isSupported = targetPlatform.isLinux;

in
rec {
  # ==========================================================================
  # Mold Linker
  # ==========================================================================

  mold =
    if isSupported then
      mkLinker {
        name = "mold";
        binary = "${pkgs.mold}/bin/mold";
        # Use full path so compiler doesn't need mold on PATH
        driverFlag = "-fuse-ld=${pkgs.mold}/bin/mold";

        capabilities = moldCapabilities;

        platformFlags =
          platform:
          if platform.isLinux then
            [
              # Mold-specific optimizations
              "-Wl,--enable-new-dtags"
            ]
          else
            [ ];

        runtimeInputs = [ pkgs.mold ];
        environment = { };
      }
    else
      null;

  # ==========================================================================
  # Availability Check
  # ==========================================================================

  isAvailable = isSupported && pkgs ? mold;
}
