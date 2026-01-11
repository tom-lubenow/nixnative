# project.nix - Build definition for the header-only library example
#
# Demonstrates a header-only library consumed by an executable.

{ pkgs, native }:

let
  proj = native.project {
    root = ./.;
  };

  vec3Lib = proj.headerOnly {
    name = "vec3";
    publicIncludeDirs = [ ./include ];
  };

  testApp = proj.executable {
    name = "header-only-test";
    sources = [ "main.cc" ];
    libraries = [ vec3Lib ];
  };

  testHeaderOnly = native.test {
    name = "test-header-only";
    executable = testApp;
    expectedOutput = "a + b = (5, 7, 9)";
  };

in {
  packages = {
    inherit testApp;
    headerOnlyExample = testApp;
    default = testApp;
  };

  checks = {
    inherit testHeaderOnly;
  };
}
