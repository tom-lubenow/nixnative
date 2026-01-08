# project.nix - Build definition for the library example
#
# Demonstrates building a static library that can be consumed by other targets.

{ pkgs, native }:

let
  proj = native.project {
    root = ./.;
  };

  mathLibrary = proj.staticLib {
    name = "libmath-example";
    sources = [ "src/math.cc" ];
    includeDirs = [ "include" ];
    publicIncludeDirs = [ "include" ];
  };

  mathLibraryTest = proj.executable {
    name = "math-library-test";
    root = ./test;
    sources = [ "main.cc" ];
    libraries = [ mathLibrary ];
  };

  testMathLibrary = native.test {
    name = "test-math-library";
    executable = mathLibraryTest;
    expectedOutput = "5 12";
  };

in {
  packages = {
    inherit mathLibrary mathLibraryTest;
  };

  checks = {
    inherit testMathLibrary;
  };
}
