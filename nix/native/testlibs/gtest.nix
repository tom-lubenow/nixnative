# GoogleTest implementation for nixnative
#
# Provides gtest and gmock test libraries.
#
# Usage:
#   # Without main (you provide main())
#   libraries = [ native.testLibs.gtest ];
#
#   # With main (gtest provides main())
#   libraries = [ native.testLibs.gtest.withMain ];
#
#   # GMock (includes gtest)
#   libraries = [ native.testLibs.gmock.withMain ];
#
{
  pkgs,
  lib,
  mkTestLib,
}:

let
  pkg = pkgs.gtest;
  # gtest uses split outputs: lib in default, headers in dev
  libDir = "${pkg}/lib";
  includeDir = "${pkg.dev}/include";

in
rec {
  # ==========================================================================
  # GoogleTest
  # ==========================================================================

  gtest = mkTestLib {
    name = "gtest";
    package = pkg;
    includeDirs = [ includeDir ];
    libraries = [
      "-L${libDir}"
      "-Wl,-rpath,${libDir}"
      "-lgtest"
    ];
    mainLibrary = "-lgtest_main";
    # Include dev output for headers in sandbox
    extraEvalInputs = [ pkg.dev ];
  };

  # ==========================================================================
  # GoogleMock (includes GoogleTest)
  # ==========================================================================

  gmock = mkTestLib {
    name = "gmock";
    package = pkg;
    includeDirs = [ includeDir ];
    libraries = [
      "-L${libDir}"
      "-Wl,-rpath,${libDir}"
      "-lgmock"
      "-lgtest"
    ];
    mainLibrary = "-lgmock_main";
    # Include dev output for headers in sandbox
    extraEvalInputs = [ pkg.dev ];
  };
}
