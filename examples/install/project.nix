{ pkgs, native }:

let
  # Static library (objects for internal use)
  staticLibObjects = native.staticLib {
    name = "mylib-static";
    root = ./.;
    sources = [ "lib.cc" ];
    publicIncludeDirs = [ ./. ];
  };

  # Static archive for installation/external distribution
  staticLib = native.archive { lib = staticLibObjects; };

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
