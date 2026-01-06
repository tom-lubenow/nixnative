# project.nix - Build definition for the library example
#
# Demonstrates building a static library that can be consumed by other targets.

{ pkgs, native }:

native.project {
  modules = [
    {
      native = {
        root = ./.;

        targets = {
          mathLibrary = {
            type = "staticLib";
            name = "libmath-example";
            sources = [ "src/math.cc" ];
            includeDirs = [ "include" ];
            publicIncludeDirs = [ "include" ];
          };

          mathLibraryTest = {
            type = "executable";
            name = "math-library-test";
            root = ./test;
            sources = [ "main.cc" ];
            libraries = [ { target = "mathLibrary"; } ];
          };
        };

        tests.mathLibrary = {
          executable = "mathLibraryTest";
          expectedOutput = "5 12";
        };
      };
    }
  ];
}
