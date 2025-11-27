{ pkgs, native }:

let
  root = ./.;
  includeDirs = [ "include" ];
  sources = [ "src/math.cc" ];

  # Using high-level API
  mathLibrary = native.staticLib {
    name = "math-example";
    inherit root includeDirs sources;
    publicIncludeDirs = includeDirs;
  };

in {
  mathLibrary = mathLibrary;
}
