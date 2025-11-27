# GCC compiler implementation for nixnative
#
# Provides GCC variants using the mkCompiler factory.
#
{ pkgs, lib, mkCompiler, gccFlagTranslators }:

let
  inherit (lib) optionals optionalAttrs;

  # Helper to create a GCC compiler for a specific version
  mkGCC = { gccPackage, name ? "gcc${gccPackage.version}" }:
    let
      gcc = gccPackage;
      targetPlatform = pkgs.stdenv.targetPlatform;
      isDarwin = targetPlatform.isDarwin;

      # GCC on Darwin needs special handling
      # Note: GCC on macOS is less common and may have limitations
      darwinFlags =
        if isDarwin then [
          # GCC on Darwin may need explicit stdlib specification
        ]
        else [];

      darwinEnv =
        if isDarwin then {
          # Darwin-specific environment if needed
        }
        else {};
    in
    mkCompiler {
      inherit name;
      cc = "${gcc}/bin/gcc";
      cxx = "${gcc}/bin/g++";
      version = gcc.version;

      capabilities = {
        lto = { thin = false; full = true; };  # GCC doesn't have thin LTO
        sanitizers = [ "address" "thread" "undefined" "leak" ]
          ++ optionals (!isDarwin) [ "memory" ];
        coverage = true;
        modules = false;  # GCC modules support is experimental
        pch = true;
        colorDiagnostics = true;
      };

      flagTranslators = gccFlagTranslators;

      defaultCFlags = [];
      defaultCxxFlags = [
        "-std=c++20"
        "-fdiagnostics-color=always"
        "-Wall"
        "-Wextra"
      ] ++ darwinFlags;

      runtimeInputs = [
        gcc
        pkgs.binutils
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gawk
      ];

      environment = darwinEnv;

      package = gcc;
    };

in rec {
  # ==========================================================================
  # GCC Compiler Variants
  # ==========================================================================

  # GCC 13
  gcc13 = mkGCC { gccPackage = pkgs.gcc13; };

  # GCC 14 (if available)
  gcc14 =
    if pkgs ? gcc14
    then mkGCC { gccPackage = pkgs.gcc14; }
    else null;

  # GCC 12
  gcc12 = mkGCC { gccPackage = pkgs.gcc12; };

  # Default GCC (13)
  gcc = gcc13;

  # ==========================================================================
  # Helper: Get bintools for GCC
  # ==========================================================================

  getBintools = compiler: {
    ar = "${pkgs.binutils}/bin/ar";
    ranlib = "${pkgs.binutils}/bin/ranlib";
    nm = "${pkgs.binutils}/bin/nm";
    objcopy = "${pkgs.binutils}/bin/objcopy";
    strip = "${pkgs.binutils}/bin/strip";
  };
}
