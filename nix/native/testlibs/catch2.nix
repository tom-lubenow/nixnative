# Catch2 implementation for nixnative
#
# Provides Catch2 v3 test library.
#
# Usage:
#   # Without main (you provide main())
#   libraries = [ native.testLibs.catch2 ];
#
#   # With main (Catch2 provides main())
#   libraries = [ native.testLibs.catch2.withMain ];
#
{
  pkgs,
  lib,
  mkTestLib,
}:

let
  pkg = pkgs.catch2_3;
  libDir = "${pkg}/lib";
  includeDir = "${pkg}/include";

in
rec {
  # ==========================================================================
  # Catch2 v3
  # ==========================================================================

  catch2 = mkTestLib {
    name = "catch2";
    package = pkg;
    includeDirs = [ includeDir ];
    libraries = [ "${libDir}/libCatch2.a" ];
    mainLibrary = "${libDir}/libCatch2Main.a";
  };
}
