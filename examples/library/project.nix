{ pkgs, cpp }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/math.cc" ];

  mathLibrary = cpp.mkStaticLib {
    name = "math-example";
    inherit root includeDirs sources;
    publicIncludeDirs = includeDirs;
  };

in {
  mathLibrary = mathLibrary;
}
