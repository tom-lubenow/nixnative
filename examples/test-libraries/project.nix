# project.nix - Build definition for the test-libraries example
#
# This file demonstrates how to use test libraries (gtest, catch2, doctest)
# with nixnative. Each test framework is shown as a separate executable.

{ pkgs, native }:

native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets = {
          gtestExample = {
            type = "executable";
            name = "gtest-example";
            sources = [ "src/gtest_tests.cc" ];
            libraries = [ native.testLibs.gtest.withMain ];
          };

          gmockExample = {
            type = "executable";
            name = "gmock-example";
            sources = [ "src/gmock_tests.cc" ];
            libraries = [ native.testLibs.gmock.withMain ];
          };

          catch2Example = {
            type = "executable";
            name = "catch2-example";
            sources = [ "src/catch2_tests.cc" ];
            libraries = [ native.testLibs.catch2.withMain ];
          };

          doctestExample = {
            type = "executable";
            name = "doctest-example";
            sources = [ "src/doctest_tests.cc" ];
            libraries = [ native.testLibs.doctest ];
          };
        };

        tests = {
          gtestExample = { executable = "gtestExample"; };
          gmockExample = { executable = "gmockExample"; };
          catch2Example = { executable = "catch2Example"; };
          doctestExample = { executable = "doctestExample"; };
        };
      };
    }
  ];
}
