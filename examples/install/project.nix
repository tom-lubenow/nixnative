{ pkgs, native }:

let
  # Static library
  staticLib = native.staticLib {
    name = "mylib-static";
    root = ./.;
    sources = [ "lib.cc" ];
    publicIncludeDirs = [ ./. ];
  };

  # Shared library
  sharedLib = native.sharedLib {
    name = "mylib-shared";
    root = ./.;
    sources = [ "lib.cc" ];
    publicIncludeDirs = [ ./. ];
  };

in {
  inherit staticLib sharedLib;
  installExample = staticLib;
}
