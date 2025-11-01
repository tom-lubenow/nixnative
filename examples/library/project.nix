{ pkgs, cpp }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/math.cc" ];
  toolchain = cpp.toolchains.clang;

  math = cpp.mkStaticLib {
    name = "math-example";
    inherit root includeDirs sources;
    depsManifest = ./deps.json;
    toolchain = toolchain;
    publicIncludeDirs = includeDirs;
  };

in {
  mathLibrary = math;
}
