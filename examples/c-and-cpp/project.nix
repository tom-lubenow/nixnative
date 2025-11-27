{ pkgs, native }:

let
  # Mixed sources in one target
  mixedApp = native.executable {
    name = "mixed-app";
    root = ./.;
    sources = [
      "clib.c"
      "main.cc"
    ];
    includeDirs = [ "include" ];
  };

  # C library as separate target
  cLib = native.staticLib {
    name = "clib";
    root = ./.;
    sources = [ "clib.c" ];
    includeDirs = [ "include" ];
    publicIncludeDirs = [ "include" ];
  };

  # C++ app using C library
  cppApp = native.executable {
    name = "cpp-app";
    root = ./.;
    sources = [ "main.cc" ];
    includeDirs = [ "include" ];
    libraries = [ cLib ];
  };

in {
  inherit mixedApp cLib cppApp;
  cAndCppExample = mixedApp;
}
