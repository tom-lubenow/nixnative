# project.nix - Build definition for the C and C++ mixed example
#
# Demonstrates building with mixed C and C++ source files.

{ pkgs, native }:

let
  proj = native.project {
    root = ./.;
  };

  # Single executable with mixed C/C++ sources
  mixedApp = proj.executable {
    name = "mixed-app";
    sources = [
      "clib.c"
      "main.cc"
    ];
    includeDirs = [ "include" ];
  };

  # C library as a static lib
  cLib = proj.staticLib {
    name = "libclib";
    sources = [ "clib.c" ];
    includeDirs = [ "include" ];
    publicIncludeDirs = [ "include" ];
  };

  # C++ app linking to C library
  cppApp = proj.executable {
    name = "cpp-app";
    sources = [ "main.cc" ];
    includeDirs = [ "include" ];
    libraries = [ cLib ];
  };

  testMixedApp = native.test {
    name = "test-mixed-app";
    executable = mixedApp;
    expectedOutput = "Mixed C/C++ working correctly!";
  };

  testCppApp = native.test {
    name = "test-cpp-app";
    executable = cppApp;
    expectedOutput = "Mixed C/C++ working correctly!";
  };

in {
  packages = {
    inherit mixedApp cLib cppApp;
  };

  checks = {
    inherit testMixedApp testCppApp;
  };
}
