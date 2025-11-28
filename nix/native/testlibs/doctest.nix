# doctest implementation for nixnative
#
# Provides doctest header-only test library.
#
# doctest is header-only, so there are no libraries to link.
# You must define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN in exactly one
# source file, or define DOCTEST_CONFIG_IMPLEMENT and provide your own main().
#
# Usage:
#   # Standard usage - define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN in one .cpp file
#   libraries = [ native.testLibs.doctest ];
#
# Example test file:
#   #define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#   #include <doctest/doctest.h>
#
#   TEST_CASE("example") {
#       CHECK(1 + 1 == 2);
#   }
#
{
  pkgs,
  lib,
  mkTestLib,
}:

let
  pkg = pkgs.doctest;
  includeDir = "${pkg}/include";

in
rec {
  # ==========================================================================
  # doctest (header-only)
  # ==========================================================================

  doctest = mkTestLib {
    name = "doctest";
    package = pkg;
    includeDirs = [ includeDir ];
    libraries = [ ]; # Header-only, no libraries needed
    mainLibrary = null; # Main is provided via DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
  };
}
