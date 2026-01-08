# project.nix - Build definition for the test-libraries example
#
# This file demonstrates how to use test libraries (gtest, catch2, doctest)
# with nixnative. Each test framework is shown as a separate executable.

{ pkgs, native }:

let
  proj = native.project {
    root = ./.;
  };

  gtestExample = proj.executable {
    name = "gtest-example";
    sources = [ "src/gtest_tests.cc" ];
    libraries = [ native.testLibs.gtest.withMain ];
  };

  gmockExample = proj.executable {
    name = "gmock-example";
    sources = [ "src/gmock_tests.cc" ];
    libraries = [ native.testLibs.gmock.withMain ];
  };

  catch2Example = proj.executable {
    name = "catch2-example";
    sources = [ "src/catch2_tests.cc" ];
    libraries = [ native.testLibs.catch2.withMain ];
  };

  doctestExample = proj.executable {
    name = "doctest-example";
    sources = [ "src/doctest_tests.cc" ];
    libraries = [ native.testLibs.doctest ];
  };

  testGtest = native.test {
    name = "test-gtest";
    executable = gtestExample;
  };

  testGmock = native.test {
    name = "test-gmock";
    executable = gmockExample;
  };

  testCatch2 = native.test {
    name = "test-catch2";
    executable = catch2Example;
  };

  testDoctest = native.test {
    name = "test-doctest";
    executable = doctestExample;
  };

in {
  packages = {
    inherit gtestExample gmockExample catch2Example doctestExample;
  };

  checks = {
    inherit testGtest testGmock testCatch2 testDoctest;
  };
}
