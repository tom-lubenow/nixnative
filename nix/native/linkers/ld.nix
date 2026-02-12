# GNU ld linker implementation for nixnative
#
# The classic GNU linker. Slower than modern alternatives but
# highly compatible and well-tested.
#
{
  pkgs,
  lib,
  mkLinker,
  ldCapabilities,
}:

let
  inherit (lib) optionals;
  targetPlatform = pkgs.stdenv.targetPlatform;

  # GNU ld is available on Linux
  isSupported = targetPlatform.isLinux;

in
rec {
  # ==========================================================================
  # GNU ld Linker
  # ==========================================================================

  ld =
    if isSupported then
      mkLinker {
        name = "ld";
        binary = "${pkgs.binutils}/bin/ld";
        driverFlag = "-fuse-ld=bfd"; # BFD is the backend name for GNU ld

        capabilities = ldCapabilities;
        supports = {
          features = [ "lto" ];
        };

        platformFlags =
          platform:
          if platform.isLinux then
            [
              # GNU ld specific flags if needed
            ]
          else
            [ ];

        runtimeInputs = [ pkgs.binutils ];
        environment = { };
      }
    else
      null;

  # Alias for clarity
  gnuLd = ld;
  bfd = ld;

  # ==========================================================================
  # Availability Check
  # ==========================================================================

  isAvailable = isSupported;
}
