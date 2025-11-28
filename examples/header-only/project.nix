{ pkgs, native }:

let
  # Header-only library
  vec3Lib = native.headerOnly {
    name = "vec3";
    publicIncludeDirs = [ ./include ];
  };

  # Test executable that uses the header-only library
  testApp = native.executable {
    name = "header-only-test";
    root = ./.;
    sources = [ "main.cc" ];
    libraries = [ vec3Lib ];
  };

in {
  inherit testApp;
  headerOnlyExample = testApp;
}
