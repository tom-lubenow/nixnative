# Darwin ld64 linker implementation for nixnative
#
# The macOS system linker (ld64). This is the default and often
# only option for linking on Darwin.
#
# NOTE: This module is the quarantine zone for all Darwin-specific linker logic.
# No other module should contain Darwin linker configuration.
#
{ pkgs, mkLinker }:

let
  targetPlatform = pkgs.stdenv.targetPlatform;
  isDarwin = targetPlatform.isDarwin;

  # Darwin ld64 capabilities (quarantined here)
  darwinLdCapabilities = {
    lto = true;
    thinLto = true;
    parallelLinking = false;
    icf = false;
    splitDwarf = false;
  };

in rec {
  # ==========================================================================
  # Darwin ld64 Linker
  # ==========================================================================

  darwinLd =
    if isDarwin then
      let
        sdkRoot = pkgs.apple-sdk.sdkroot;
        deploymentTarget = targetPlatform.darwinMinVersion or "11.0";
      in
      mkLinker {
        name = "ld64";
        binary = "${pkgs.stdenv.cc.bintools.bintools}/bin/ld";
        driverFlag = "";  # ld64 is the default on Darwin

        capabilities = darwinLdCapabilities;

        platformFlags = platform: [
          "-Wl,-syslibroot,${builtins.toString sdkRoot}"
          "-F${builtins.toString sdkRoot}/System/Library/Frameworks"
        ];

        # Darwin doesn't use --start-group/--end-group
        groupFlags = _: libs: libs;

        runtimeInputs = [
          pkgs.stdenv.cc.bintools.bintools
          pkgs.darwin.cctools
          pkgs.apple-sdk
        ];

        environment = {
          SDKROOT = builtins.toString sdkRoot;
          MACOSX_DEPLOYMENT_TARGET = deploymentTarget;
        };
      }
    else null;

  # ==========================================================================
  # Availability Check
  # ==========================================================================

  isAvailable = isDarwin;

  # ==========================================================================
  # Darwin-Specific Helpers
  # ==========================================================================

  # Get framework link flags
  linkFrameworks = frameworks:
    builtins.concatMap (f: [ "-framework" f ]) frameworks;

  # Get framework search path flags
  frameworkSearchPaths = paths:
    builtins.concatMap (p: [ "-F" p ]) paths;

  # Dead code stripping (Darwin-specific)
  deadCodeStripping = [ "-Wl,-dead_strip" ];

  # Export dynamic symbols (for plugins/dylibs)
  exportDynamic = [ "-Wl,-export_dynamic" ];
}
