# project.nix - Build definition for the test-libraries example
#
# This file demonstrates how to use test libraries (gtest, catch2, doctest)
# with nixnative. Each test framework is shown as a separate executable.

{ pkgs, native }:

let
  root = ./.;

  # ==========================================================================
  # GoogleTest Example
  # ==========================================================================
  #
  # Uses native.testLibs.gtest.withMain to get gtest with the default main()
  # provided by gtest_main. This is the most common usage pattern.
  #
  gtestExample = native.executable {
    name = "gtest-example";
    inherit root;
    sources = [ "src/gtest_tests.cc" ];
    libraries = [ native.testLibs.gtest.withMain ];
  };

  # ==========================================================================
  # GoogleMock Example
  # ==========================================================================
  #
  # Uses native.testLibs.gmock.withMain for mocking support.
  # GMock includes GTest, so you get both.
  #
  gmockExample = native.executable {
    name = "gmock-example";
    inherit root;
    sources = [ "src/gmock_tests.cc" ];
    libraries = [ native.testLibs.gmock.withMain ];
  };

  # ==========================================================================
  # Catch2 Example
  # ==========================================================================
  #
  # Uses native.testLibs.catch2.withMain for Catch2 with default main().
  #
  catch2Example = native.executable {
    name = "catch2-example";
    inherit root;
    sources = [ "src/catch2_tests.cc" ];
    libraries = [ native.testLibs.catch2.withMain ];
  };

  # ==========================================================================
  # doctest Example
  # ==========================================================================
  #
  # doctest is header-only. The main() is provided by defining
  # DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN before including doctest.h.
  #
  doctestExample = native.executable {
    name = "doctest-example";
    inherit root;
    sources = [ "src/doctest_tests.cc" ];
    libraries = [ native.testLibs.doctest ];
  };

in
{
  inherit
    gtestExample
    gmockExample
    catch2Example
    doctestExample
    ;
}
